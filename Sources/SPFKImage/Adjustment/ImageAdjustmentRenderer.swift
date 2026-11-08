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

        if adjustments.vibrance != 0 {
            let filter = CIFilter.vibrance()
            filter.inputImage = output
            filter.amount = Float(adjustments.vibrance)
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
            filter.radius = Float(sharpnessRadius * sourceScale)
            output = filter.outputImage ?? output
        }

        return output.cropped(to: image.extent)
    }

    /// Renders `source` with `adjustments`, then `orientation`, into a bitmap in the source's color space
    /// and bit depth.
    ///
    /// Eager (`deferred: false`), so the cost lands here rather than wherever the image is first drawn.
    public func render(
        _ adjustments: ImageAdjustmentDescription,
        orientation: ImageOrientationEdit = .up,
        source: CGImage,
        sourceScale: Double = 1
    ) -> CGImage? {
        autoreleasepool {
            let adjusted = Self.apply(adjustments, to: CIImage(cgImage: source), sourceScale: sourceScale)
            let output = orientation.apply(to: adjusted)

            return context.createCGImage(
                output,
                from: output.extent,
                format: source.bitsPerComponent > 8 ? .RGBA16 : .RGBA8,
                colorSpace: Self.renderColorSpace(for: source),
                deferred: false
            )
        }
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
}
