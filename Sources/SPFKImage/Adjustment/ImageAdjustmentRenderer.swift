// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Applies an ``ImageAdjustmentDescription`` to an image through Core Image.
///
/// Holds one `CIContext` to reuse: a new context per render costs more than the filter chain. Filters
/// are built inside each call and never leave it, since `CIFilter` is not `Sendable` and the context
/// and images are.
public struct ImageAdjustmentRenderer: Sendable {
    public let context: CIContext

    public init(context: CIContext = CIContext()) {
        self.context = context
    }

    /// `image` with `adjustments` applied in the order the description documents, cropped to the input's
    /// extent. Lazy: nothing renders until the result is drawn.
    ///
    /// `sourceScale` is `image`'s size relative to the full-resolution source (see
    /// ``sourceScale(of:fullWidth:fullHeight:)``), so a filter sized in pixels looks the same on a
    /// downsampled preview as in the saved file.
    public static func apply(
        _ adjustments: ImageAdjustmentDescription,
        to image: CIImage,
        sourceScale: Double = 1
    ) -> CIImage {
        let adjustments = adjustments.effective
        guard !adjustments.isEmpty else { return image }

        var output = image

        if adjustments.noiseReduction != 0 {
            output = noiseReduction(output, adjustments.noiseReduction * min(1, sourceScale))
        }

        if adjustments.exposure != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = output
            filter.ev = Float(adjustments.exposure)
            output = filter.outputImage ?? output
        }

        if adjustments.temperature != 0 || adjustments.tint != 0 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = output
            filter.neutral = CIVector(
                x: neutralKelvin + adjustments.temperature * kelvinPerUnit,
                y: adjustments.tint * tintPerUnit
            )
            filter.targetNeutral = CIVector(x: neutralKelvin, y: 0)
            output = filter.outputImage ?? output
        }

        if adjustments.vibrance != 0 {
            let filter = CIFilter.vibrance()
            filter.inputImage = output
            filter.amount = Float(adjustments.vibrance)
            output = filter.outputImage ?? output
        }

        if adjustments.blackPoint != 0 {
            output = toneCurve(output, blackPointCurve(adjustments.blackPoint))
        }

        if adjustments.hasLevels {
            output = toneCurve(output, levelsCurve(adjustments))
        }

        if adjustments.highlights != 0 || adjustments.shadows != 0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = output
            filter.highlightAmount = Float(1 + adjustments.highlights)
            filter.shadowAmount = Float(adjustments.shadows)
            output = filter.outputImage ?? output
        }

        if adjustments.brightness != 0 {
            output = toneCurve(output, brightnessCurve(adjustments.brightness))
        }

        if adjustments.brilliance != 0 {
            output = brilliance(output, adjustments.brilliance)
        }

        if adjustments.contrast != 0 || adjustments.saturation != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = output
            filter.contrast = Float(pow(2, adjustments.contrast))
            filter.saturation = Float(1 + adjustments.saturation)
            filter.brightness = 0
            output = filter.outputImage ?? output
        }

        if adjustments.definition != 0 {
            output = definition(output, adjustments.definition)
        }

        if adjustments.sepia != 0 {
            let filter = CIFilter.sepiaTone()
            filter.inputImage = output
            filter.intensity = Float(adjustments.sepia)
            output = filter.outputImage ?? output
        }

        if adjustments.sharpness != 0 {
            let filter = CIFilter.sharpenLuminance()
            filter.inputImage = output
            filter.sharpness = Float(adjustments.sharpness * maximumSharpness)
            filter.radius = Float(sharpnessRadius * sourceScale)
            output = filter.outputImage ?? output
        }

        if adjustments.vignette != 0 {
            let extent = image.extent
            let filter = CIFilter.vignetteEffect()
            filter.inputImage = output
            filter.center = CGPoint(x: extent.midX, y: extent.midY)
            filter.radius = Float(min(extent.width, extent.height) * neutralVignetteRadius
                * pow(2, adjustments.vignetteRadius))
            filter.falloff = Float(neutralVignetteFalloff * (1 + adjustments.vignetteSoftness))
            filter.intensity = Float(adjustments.vignette)
            output = filter.outputImage ?? output
        }

        return output.cropped(to: image.extent)
    }

    /// `CIToneCurve` works on sRGB-encoded values and clamps its output to 0…1.
    static func toneCurve(_ image: CIImage, _ points: [CGPoint]) -> CIImage {
        let filter = CIFilter.toneCurve()
        filter.inputImage = image
        filter.point0 = points[0]
        filter.point1 = points[1]
        filter.point2 = points[2]
        filter.point3 = points[3]
        filter.point4 = points[4]
        return filter.outputImage ?? image
    }

    /// A straight line in sRGB-encoded values. Positive maps `value × maximumBlackPoint` to 0 and
    /// stretches the rest; negative raises 0 to `−value × maximumBlackPoint`. White stays at 1.
    static func blackPointCurve(_ value: Double) -> [CGPoint] {
        let shift = abs(value) * maximumBlackPoint
        return curvePositions.map { x in
            value > 0
                ? CGPoint(x: shift + (1 - shift) * x, y: x)
                : CGPoint(x: x, y: shift + (1 - shift) * x)
        }
    }

    /// Lifts or lowers the mid-tones along `4x(1 − x)`, so black and white stay fixed.
    static func brightnessCurve(_ value: Double) -> [CGPoint] {
        curvePositions.map { x in
            CGPoint(x: x, y: x + value * maximumBrightnessLift * 4 * x * (1 - x))
        }
    }

    /// Renders `source` with `adjustments`, then `orientation`, into a bitmap in the source's color space
    /// and bit depth.
    ///
    /// With `crop`, only that part of the oriented output renders, in its pixels with the origin at the
    /// top left, expanded to whole pixels and limited to the output. The adjustments still see the
    /// whole image, so a crop matches the same region cut from a full render.
    ///
    /// Eager (`deferred: false`), so the cost lands here rather than wherever the image is first drawn.
    public func render(
        _ adjustments: ImageAdjustmentDescription,
        orientation: ImageOrientationEdit = .up,
        source: CGImage,
        sourceScale: Double = 1,
        crop: CGRect? = nil
    ) -> CGImage? {
        autoreleasepool {
            let adjusted = Self.apply(adjustments, to: CIImage(cgImage: source), sourceScale: sourceScale)
            let output = orientation.apply(to: adjusted)
            let region = crop.map { Self.coreImageRect(topLeft: $0, in: output.extent) } ?? output.extent

            guard !region.isEmpty else { return nil }

            return context.createCGImage(
                output,
                from: region,
                format: source.bitsPerComponent > 8 ? .RGBA16 : .RGBA8,
                colorSpace: Self.renderColorSpace(for: source),
                deferred: false
            )
        }
    }

    /// `rect`, with its origin at the top left of `extent`, in Core Image's bottom-left coordinates,
    /// expanded to whole pixels and limited to `extent`.
    static func coreImageRect(topLeft rect: CGRect, in extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + rect.minX,
            y: extent.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        ).integral.intersection(extent)
    }

    /// The scale of an image `extent` decoded from a source of `fullWidth` × `fullHeight` pixels, or 1
    /// when either is unknown. Compares the longer sides, so an upright decode of a rotated file still
    /// matches its unoriented pixel dimensions.
    public static func sourceScale(of extent: CGRect, fullWidth: Int?, fullHeight: Int?) -> Double {
        guard let fullWidth, let fullHeight, max(fullWidth, fullHeight) > 0 else { return 1 }
        return Double(max(extent.width, extent.height)) / Double(max(fullWidth, fullHeight))
    }

    /// The source's color space when it is RGB, which `createCGImage` requires; sRGB otherwise.
    static func renderColorSpace(for image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb {
            return space
        }

        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    // MARK: - Mapping from slider positions

    /// `CITemperatureAndTint`'s identity white point.
    static let neutralKelvin: CGFloat = 6500
    static let kelvinPerUnit: CGFloat = 3500
    static let tintPerUnit: CGFloat = 100
    /// Top of `CISharpenLuminance`'s slider range.
    static let maximumSharpness: Double = 2
    /// `CISharpenLuminance`'s default radius, in full-resolution pixels.
    static let sharpnessRadius: Double = 1.69
    /// Where the vignette begins at a neutral radius, as a fraction of the shorter side. Each unit of
    /// radius doubles or halves it.
    static let neutralVignetteRadius: CGFloat = 0.75
    /// How far a full black point moves black, in sRGB-encoded values.
    static let maximumBlackPoint: Double = 0.25
    /// How far full brightness moves mid-gray, in sRGB-encoded values.
    static let maximumBrightnessLift: Double = 0.2
    /// How far full positive and full negative brilliance move the base at each of
    /// ``curvePositions``, in sRGB-encoded values.
    static let brillianceLift: [Double] = [0, 0.10, 0.14, 0.04, 0]
    static let brillianceDrop: [Double] = [0, 0.10, 0.21, 0.04, 0]
    /// The detail gain added at full positive and full negative brilliance.
    static let brillianceDetailGain: Double = 0.6
    static let brillianceDarkDetailGain: Double = 0.2
    /// The detail gain added at full definition, and how far it moves the base.
    static let maximumDefinitionGain: Double = 1
    static let definitionLift: [Double] = [0, -0.02, -0.02, 0, 0]
    /// Added to both luminances before the local-tone ratio, so black does not divide by zero.
    static let ratioFloor: Double = 0.004
    /// The local-tone base's shorter side, in pixels, before it is upsampled along the image's edges.
    static let localToneBaseSize: Double = 128
    /// `CIGuidedFilter`'s radius and epsilon for the local-tone base; epsilon is in sRGB-encoded
    /// luminance squared.
    static let localToneGuideRadius: Double = 3
    static let localToneEpsilon: Double = 0.01
    /// The x positions of `CIToneCurve`'s five points at identity.
    static let curvePositions: [Double] = [0, 0.25, 0.5, 0.75, 1]
    /// `CIVignetteEffect`'s falloff at neutral softness; the slider spans its 0…1.
    static let neutralVignetteFalloff: Double = 0.5
}
