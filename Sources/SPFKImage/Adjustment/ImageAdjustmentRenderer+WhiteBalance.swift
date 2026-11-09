// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

extension ImageAdjustmentRenderer {
    /// The Temperature and Tint whose step renders `color` gray, each limited to its slider range, so a
    /// color beyond reach comes back as the nearest the range allows.
    ///
    /// `CITemperatureAndTint`'s math is not public, so this searches it: a damped Newton iteration on
    /// 1×1 renders of the renderer's own step.
    public static func whiteBalance(neutralizing color: CIColor) -> (temperature: Double, tint: Double) {
        guard let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let converted = color.colorSpace.name == linear.name ? color : convert(color, to: linear),
              min(converted.red, converted.green, converted.blue) > 0
        else { return (0, 0) }

        let pixel = CIImage(color: converted).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))

        func residual(_ temperature: Double, _ tint: Double) -> SIMD2<Double>? {
            let output = temperature == 0 && tint == 0
                ? pixel
                : temperatureAndTint(pixel, temperature: temperature, tint: tint)
            guard let rgb = averagePixel(of: output), rgb.x > 0, rgb.y > 0, rgb.z > 0 else { return nil }
            return SIMD2(log(rgb.x / rgb.y), log(rgb.z / rgb.y))
        }

        let temperatureRange = ImageAdjustmentDescription.Parameter.temperature.range
        let tintRange = ImageAdjustmentDescription.Parameter.tint.range
        var solution = SIMD2<Double>(0, 0)
        guard var current = residual(0, 0) else { return (0, 0) }

        for _ in 0 ..< whiteBalanceIterations {
            guard length(current) > whiteBalanceTolerance else { break }

            // Central differences: a one-sided step from 0 lands in the filter's identity zone.
            let h = whiteBalanceDerivativeStep
            guard let tPlus = residual(solution.x + h, solution.y), let tMinus = residual(solution.x - h, solution.y),
                  let nPlus = residual(solution.x, solution.y + h), let nMinus = residual(solution.x, solution.y - h)
            else { break }

            let dT = (tPlus - tMinus) / (2 * h)
            let dN = (nPlus - nMinus) / (2 * h)
            let determinant = dT.x * dN.y - dN.x * dT.y
            guard determinant != 0 else { break }

            let step = SIMD2(dN.y * current.x - dN.x * current.y, -dT.y * current.x + dT.x * current.y) / determinant

            // Halve the step until the residual shrinks, so an overshoot near a range limit cannot diverge.
            var scale = 1.0
            var improved = false

            while scale > 1e-3 {
                let candidate = SIMD2(
                    (solution.x - scale * step.x).limited(to: temperatureRange),
                    (solution.y - scale * step.y).limited(to: tintRange)
                )

                if let next = residual(candidate.x, candidate.y), length(next) < length(current) {
                    solution = candidate
                    current = next
                    improved = true
                    break
                }
                scale /= 2
            }

            guard improved else { break }
        }

        return (solution.x, solution.y)
    }

    /// The average color of `image`'s near-gray pixels, skipping clipped and near-black ones, or nil
    /// when too few are near gray to say what gray is.
    public static func neutralEstimate(of image: CIImage) -> CIColor? {
        let longer = max(image.extent.width, image.extent.height)
        guard longer > 0, let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return nil }

        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(min(1, whiteBalanceAnalysisSize / longer))
        filter.aspectRatio = 1
        guard let reduced = filter.outputImage else { return nil }

        let bounds = reduced.extent.integral.intersection(reduced.extent)
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        guard width > 0, height > 0 else { return nil }

        var pixels = [SIMD4<Float>](repeating: .zero, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            analysisContext.render(
                reduced,
                toBitmap: base,
                rowBytes: width * MemoryLayout<SIMD4<Float>>.stride,
                bounds: bounds,
                format: .RGBAf,
                colorSpace: linear
            )
        }

        var sum = SIMD3<Double>(0, 0, 0)
        var count = 0

        for pixel in pixels {
            let rgb = SIMD3(Double(pixel.x), Double(pixel.y), Double(pixel.z))
            let high = rgb.max()
            guard high < whiteBalanceClipLevel, high > whiteBalanceDarkLevel,
                  (high - rgb.min()) / high < whiteBalanceNeutralChroma
            else { continue }

            sum += rgb
            count += 1
        }

        guard Double(count) >= Double(pixels.count) * minimumNeutralFraction else { return nil }

        let mean = sum / Double(count)
        return CIColor(red: mean.x, green: mean.y, blue: mean.z, alpha: 1, colorSpace: linear)
    }

    /// Temperature and Tint neutralizing `image`'s near-gray pixels; neutral when it has too few.
    /// Every other field is neutral.
    ///
    /// `image` is the unadjusted source: the analysis must not see the Temperature and Tint it replaces.
    public static func autoWhiteBalance(for image: CIImage) -> ImageAdjustmentDescription {
        var result = ImageAdjustmentDescription()
        guard let color = neutralEstimate(of: image) else { return result }

        let balance = whiteBalance(neutralizing: color)
        result.color.temperature = balance.temperature
        result.color.tint = balance.tint
        return result
    }

    /// Temperature and Tint making the ``whiteBalanceSampleSize`` square around `point` gray, or nil when
    /// the point is outside `image`.
    ///
    /// `point` is in unit coordinates of `image` with the origin at the top left. `image` is the
    /// unadjusted source as shown, oriented: only Exposure renders before the temperature step, and it
    /// does not move hue.
    public static func whiteBalance(sampling point: CGPoint, in image: CIImage) -> (temperature: Double, tint: Double)? {
        let extent = image.extent
        guard (0 ... 1).contains(point.x), (0 ... 1).contains(point.y), !extent.isEmpty else { return nil }

        let center = CGPoint(x: extent.minX + point.x * extent.width, y: extent.maxY - point.y * extent.height)
        let side = whiteBalanceSampleSize
        let area = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
            .integral
            .intersection(extent)

        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = area

        guard !area.isEmpty, let output = filter.outputImage, let rgb = averagePixel(of: output),
              let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let color = CIColor(red: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1, colorSpace: linear)
        else { return nil }

        return whiteBalance(neutralizing: color)
    }

    /// The first pixel of `image` in linear extended sRGB.
    private static func averagePixel(of image: CIImage) -> SIMD3<Double>? {
        guard let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return nil }

        var pixel = SIMD4<Float>.zero
        withUnsafeMutableBytes(of: &pixel) { buffer in
            guard let base = buffer.baseAddress else { return }
            analysisContext.render(
                image,
                toBitmap: base,
                rowBytes: MemoryLayout<SIMD4<Float>>.stride,
                bounds: CGRect(x: image.extent.minX, y: image.extent.minY, width: 1, height: 1),
                format: .RGBAf,
                colorSpace: linear
            )
        }

        let rgb = SIMD3(Double(pixel.x), Double(pixel.y), Double(pixel.z))
        return rgb.x.isFinite && rgb.y.isFinite && rgb.z.isFinite ? rgb : nil
    }

    private static func convert(_ color: CIColor, to space: CGColorSpace) -> CIColor? {
        let components = [color.red, color.green, color.blue, color.alpha]
        guard let cgColor = CGColor(colorSpace: color.colorSpace, components: components),
              let converted = cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let values = converted.components, values.count >= 3
        else { return nil }

        return CIColor(red: values[0], green: values[1], blue: values[2], alpha: 1, colorSpace: space)
    }

    private static func length(_ value: SIMD2<Double>) -> Double {
        (value * value).sum().squareRoot()
    }

    /// For the white balance's small renders, which a shared preview context gains nothing from caching.
    static let analysisContext = CIContext(options: [.cacheIntermediates: false])

    /// The longer side, in pixels, the neutral estimate reduces an image to.
    static let whiteBalanceAnalysisSize: CGFloat = 256
    /// A pixel counts as near gray when its channels spread less than this fraction of the brightest.
    static let whiteBalanceNeutralChroma: Double = 0.3
    /// Linear values at or above this are taken as clipped, and at or below the dark level as noise.
    static let whiteBalanceClipLevel: Double = 0.95
    static let whiteBalanceDarkLevel: Double = 0.02
    /// The share of pixels that must be near gray for an estimate.
    static let minimumNeutralFraction: Double = 0.01
    /// The eyedropper's square, in pixels of the image it samples.
    public static let whiteBalanceSampleSize: CGFloat = 5
    static let whiteBalanceIterations = 12
    static let whiteBalanceTolerance: Double = 1e-5
    static let whiteBalanceDerivativeStep: Double = 0.02
}

extension Double {
    fileprivate func limited(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
