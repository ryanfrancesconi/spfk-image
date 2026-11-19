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

        // The white-balance matrix at the pinned (0.25, −0.2), rows in linear sRGB.
        let temperature = CIFilter.colorMatrix()
        temperature.inputImage = exposure.outputImage
        temperature.rVector = CIVector(x: 0.9837137915, y: -0.0496473233, z: 0.0048602319, w: 0)
        temperature.gVector = CIVector(x: 0.0025790389, y: 1.0301108797, z: 0.0044070193, w: 0)
        temperature.bVector = CIVector(x: -0.0035134187, y: -0.0165427332, z: 0.8324170052, w: 0)
        temperature.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        temperature.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)

        let highlightShadow = CIFilter.highlightShadowAdjust()
        highlightShadow.inputImage = temperature.outputImage
        highlightShadow.highlightAmount = Float(1 + a.light.highlights * 0.75)
        highlightShadow.shadowAmount = 0

        let shadowsCurve = MonotoneCubicInterpolation(
            x: [0, 0.25, 0.5, 0.75, 1],
            y: [0, 0.25 + 0.19 * a.light.shadows, 0.5 + 0.12 * a.light.shadows, 0.75, 1]
        )
        let shadows = ImageAdjustmentRenderer.colorCube(
            highlightShadow.outputImage ?? image, step: "pinnedShadows", values: [a.light.shadows]
        ) { rgb in
            let peak = rgb.max()
            return peak > 0 ? rgb * (shadowsCurve.value(at: peak) / peak) : rgb
        }

        let gain = 1 + a.light.contrast * 0.7
        let contrast = CIArithmetic.preservingRange(shadows) { image in
            let curve = CIFilter.toneCurve()
            curve.inputImage = image
            curve.point0 = CGPoint(x: 0, y: 0)
            curve.point1 = CGPoint(x: 0.25, y: 0.5 - 0.25 * gain)
            curve.point2 = CGPoint(x: 0.5, y: 0.5)
            curve.point3 = CGPoint(x: 0.75, y: 0.5 + 0.25 * gain)
            curve.point4 = CGPoint(x: 1, y: 1)
            return curve.outputImage ?? image
        }

        let controls = CIFilter.colorControls()
        controls.inputImage = contrast
        controls.contrast = 1
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
