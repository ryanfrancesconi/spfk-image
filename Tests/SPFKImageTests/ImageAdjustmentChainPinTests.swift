// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SPFKTesting
import Testing

@testable import SPFKImage

/// Pins the output of the original nine-parameter chain, so a step added to the renderer cannot move
/// where the existing steps sit relative to each other.
///
/// The reference chain and its constants are copied here rather than read from the renderer, so a
/// change to either side shows up as a mismatch.
@Suite(.tags(.file))
final class ImageAdjustmentChainPinTests {
    let context = CIContext()
    let input: CIImage

    init() throws {
        input = CIImage(cgImage: try CGImage.contentsOf(url: TestBundleResources.shared.songbird))
    }

    static let pinned = ImageAdjustmentDescription(
        light: .init(exposure: 0.4, highlights: -0.5, shadows: 0.4, contrast: 0.3),
        color: .init(saturation: -0.3, temperature: 0.25, tint: -0.2, sepia: 0.35),
        detail: .init(sharpness: 0.6)
    )

    @Test func everyExistingParameterRendersAsTheOriginalChain() throws {
        let rendered = try Self.floatPixels(ImageAdjustmentRenderer.apply(Self.pinned, to: input), context: context)
        let reference = try Self.floatPixels(Self.referenceChain(Self.pinned, input), context: context)

        try #require(rendered.count == reference.count)

        let maximumDifference = zip(rendered, reference).map { abs($0 - $1) }.max() ?? 0
        #expect(maximumDifference < 1e-4)
    }

    /// The six-step chain as it stood with nine parameters.
    static func referenceChain(_ a: ImageAdjustmentDescription, _ image: CIImage) -> CIImage {
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = image
        exposure.ev = Float(a.light.exposure)

        let temperature = CIFilter.temperatureAndTint()
        temperature.inputImage = exposure.outputImage
        temperature.neutral = CIVector(x: 6500 + a.color.temperature * 3500, y: a.color.tint * 100)
        temperature.targetNeutral = CIVector(x: 6500, y: 0)

        let highlightShadow = CIFilter.highlightShadowAdjust()
        highlightShadow.inputImage = temperature.outputImage
        highlightShadow.highlightAmount = Float(1 + a.light.highlights)
        highlightShadow.shadowAmount = Float(a.light.shadows)

        let controls = CIFilter.colorControls()
        controls.inputImage = highlightShadow.outputImage
        controls.contrast = Float(pow(2, a.light.contrast))
        controls.saturation = Float(1 + a.color.saturation)
        controls.brightness = 0

        let sepia = CIFilter.sepiaTone()
        sepia.inputImage = controls.outputImage
        sepia.intensity = Float(a.color.sepia)

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = sepia.outputImage
        sharpen.sharpness = Float(a.detail.sharpness * 2)

        return (sharpen.outputImage ?? image).cropped(to: image.extent)
    }

    /// `image` rendered to 32-bit float RGBA in extended linear sRGB, row padding removed.
    ///
    /// Through `createCGImage`: `render(toBitmap:)` reads past the end of an unfiltered CGImage-backed
    /// source.
    static func floatPixels(_ image: CIImage, context: CIContext) throws -> [Float] {
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let rendered = try #require(
            context.createCGImage(image, from: image.extent, format: .RGBAf, colorSpace: space, deferred: false)
        )
        let data = try #require(rendered.dataProvider?.data) as Data
        let rowFloats = rendered.width * 4

        return data.withUnsafeBytes { buffer in
            (0 ..< rendered.height).flatMap { row in
                let start = buffer.baseAddress?.advanced(by: row * rendered.bytesPerRow)
                return Array(UnsafeBufferPointer(start: start?.assumingMemoryBound(to: Float.self), count: rowFloats))
            }
        }
    }
}
