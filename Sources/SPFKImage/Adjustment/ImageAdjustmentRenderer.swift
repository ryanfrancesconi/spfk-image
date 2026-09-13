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
    public static func apply(_ adjustments: ImageAdjustmentDescription, to image: CIImage) -> CIImage {
        guard !adjustments.isEmpty else { return image }

        var output = image

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

        if adjustments.highlights != 0 || adjustments.shadows != 0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = output
            filter.highlightAmount = Float(1 + adjustments.highlights)
            filter.shadowAmount = Float(adjustments.shadows)
            output = filter.outputImage ?? output
        }

        if adjustments.contrast != 0 || adjustments.saturation != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = output
            filter.contrast = Float(pow(2, adjustments.contrast))
            filter.saturation = Float(1 + adjustments.saturation)
            filter.brightness = 0
            output = filter.outputImage ?? output
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
            output = filter.outputImage ?? output
        }

        return output.cropped(to: image.extent)
    }

    /// Renders `source` with `adjustments` into a bitmap in the source's color space and bit depth.
    ///
    /// Eager (`deferred: false`), so the cost lands here rather than wherever the image is first drawn.
    public func render(_ adjustments: ImageAdjustmentDescription, source: CGImage) -> CGImage? {
        autoreleasepool {
            let input = CIImage(cgImage: source)

            return context.createCGImage(
                Self.apply(adjustments, to: input),
                from: input.extent,
                format: source.bitsPerComponent > 8 ? .RGBA16 : .RGBA8,
                colorSpace: Self.renderColorSpace(for: source),
                deferred: false
            )
        }
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
}
