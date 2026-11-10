// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SPFKBase

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

        let light = adjustments.light
        let color = adjustments.color
        let detail = adjustments.detail
        var output = image

        if detail.noiseReduction != 0 {
            output = noiseReduction(output, detail.noiseReduction * min(1, sourceScale))
        }

        if light.exposure != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = output
            filter.ev = Float(light.exposure)
            output = filter.outputImage ?? output
        }

        if color.temperature != 0 || color.tint != 0 {
            output = temperatureAndTint(output, temperature: color.temperature, tint: color.tint)
        }

        if color.vibrance != 0 {
            let filter = CIFilter.vibrance()
            filter.inputImage = output
            filter.amount = Float(color.vibrance)
            output = filter.outputImage ?? output
        }

        if light.blackPoint != 0 {
            output = toneCurve(output, blackPointCurve(light.blackPoint))
        }

        if light.whitePoint != 0 {
            output = toneCurve(output, whitePointCurve(light.whitePoint))
        }

        if !adjustments.levels.isNeutral {
            output = toneCurve(output, levelsCurve(adjustments.levels))
        }

        if !adjustments.curves.isIdentity {
            output = curves(output, adjustments.curves)
        }

        if light.highlights != 0 || light.shadows != 0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = output
            filter.highlightAmount = Float(1 + light.highlights)
            filter.shadowAmount = Float(light.shadows)
            output = filter.outputImage ?? output
        }

        if light.brightness != 0 {
            output = toneCurve(output, brightnessCurve(light.brightness))
        }

        if light.brilliance != 0 {
            output = brilliance(output, light.brilliance)
        }

        if light.contrast != 0 || color.saturation != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = output
            filter.contrast = Float(pow(2, light.contrast))
            filter.saturation = Float(1 + color.saturation)
            filter.brightness = 0
            output = filter.outputImage ?? output
        }

        if detail.definition != 0 {
            output = definition(output, detail.definition)
        }

        if !adjustments.selectiveColor.isNeutral {
            output = selectiveColor(output, adjustments.selectiveColor)
        }

        if adjustments.blackAndWhite.amount != 0 {
            output = blackAndWhite(output, adjustments.blackAndWhite)
        }

        if adjustments.colorGrading.hasTint {
            output = colorGrading(output, adjustments.colorGrading)
        }

        if color.sepia != 0 {
            let filter = CIFilter.sepiaTone()
            filter.inputImage = output
            filter.intensity = Float(color.sepia)
            output = filter.outputImage ?? output
        }

        if detail.sharpness != 0 {
            let filter = CIFilter.sharpenLuminance()
            filter.inputImage = output
            filter.sharpness = Float(detail.sharpness * maximumSharpness)
            filter.radius = Float(neutralSharpnessRadius * pow(2, detail.sharpnessRadius) * sourceScale)
            output = filter.outputImage ?? output
        }

        if adjustments.vignette.amount != 0 {
            output = vignette(output, adjustments.vignette, extent: image.extent)
        }

        if adjustments.grain.amount != 0 {
            output = grain(output, adjustments.grain, origin: image.extent.origin, sourceScale: sourceScale)
        }

        return output.cropped(to: image.extent)
    }

    /// Darkens or, when negative, lightens the edges of `extent`.
    static func vignette(_ image: CIImage, _ vignette: ImageAdjustmentDescription.Vignette, extent: CGRect) -> CIImage {
        let filter = CIFilter.vignetteEffect()
        filter.inputImage = image
        filter.center = CGPoint(x: extent.midX, y: extent.midY)
        filter.radius = Float(min(extent.width, extent.height) * neutralVignetteRadius * pow(2, vignette.radius))
        filter.falloff = Float(neutralVignetteFalloff * (1 + vignette.softness))
        filter.intensity = Float(vignette.amount)
        return filter.outputImage ?? image
    }

    /// The Temperature and Tint step. Within a few kelvin of neutral `CITemperatureAndTint` renders
    /// its input unchanged.
    static func temperatureAndTint(_ image: CIImage, temperature: Double, tint: Double) -> CIImage {
        let filter = CIFilter.temperatureAndTint()
        filter.inputImage = image
        filter.neutral = CIVector(x: neutralKelvin + temperature * kelvinPerUnit, y: tint * tintPerUnit)
        filter.targetNeutral = CIVector(x: neutralKelvin, y: 0)
        return filter.outputImage ?? image
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

    /// A straight line in sRGB-encoded values. Positive maps `1 − value × maximumWhitePoint` to 1 and
    /// stretches the rest; negative lowers 1 to `1 + value × maximumWhitePoint`. Black stays at 0.
    static func whitePointCurve(_ value: Double) -> [CGPoint] {
        let scale = 1 - abs(value) * maximumWhitePoint
        return curvePositions.map { x in
            value > 0
                ? CGPoint(x: scale * x, y: x)
                : CGPoint(x: x, y: scale * x)
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
        orientation: OrientationEdit = .up,
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
    /// `CISharpenLuminance`'s default radius, in full-resolution pixels, used at a neutral sharpness
    /// radius. Each unit of radius doubles or halves it.
    static let neutralSharpnessRadius: Double = 1.69
    /// Where the vignette begins at a neutral radius, as a fraction of the shorter side. Each unit of
    /// radius doubles or halves it.
    static let neutralVignetteRadius: CGFloat = 0.75
    /// How far a full black point moves black, in sRGB-encoded values.
    static let maximumBlackPoint: Double = 0.25
    /// How far a full white point moves white, in sRGB-encoded values.
    static let maximumWhitePoint: Double = 0.25
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
