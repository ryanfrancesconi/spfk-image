// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SPFKTesting
import Testing

@testable import SPFKImage

@Suite(.tags(.file))
final class ImageAdjustmentNoiseReductionTests {
    let context = CIContext()
    let extent = CGRect(x: 0, y: 0, width: 256, height: 256)

    /// Mid-gray with per-pixel random noise of ±0.1 in each channel.
    private var noisyGray: CIImage {
        let gray = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: extent)
        let noise = CIFilter.randomGenerator().outputImage?.cropped(to: extent) ?? gray
        let scaled = CIFilter.colorMatrix()
        scaled.inputImage = noise
        scaled.rVector = CIVector(x: 0.2, y: 0, z: 0, w: 0)
        scaled.gVector = CIVector(x: 0, y: 0.2, z: 0, w: 0)
        scaled.bVector = CIVector(x: 0, y: 0, z: 0.2, w: 0)
        scaled.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        scaled.biasVector = CIVector(x: 0.4, y: 0.4, z: 0.4, w: 0)
        return scaled.outputImage?.cropped(to: extent) ?? gray
    }

    private func pixels(_ image: CIImage) throws -> [Float] {
        try ImageAdjustmentChainPinTests.floatPixels(image, context: context)
    }

    /// Root-mean-square distance of the RGB channels from their own mean.
    private func noise(_ pixels: [Float]) -> Float {
        let rgb = pixels.enumerated().filter { $0.offset % 4 != 3 }.map(\.element)
        let mean = rgb.reduce(0, +) / Float(rgb.count)
        return (rgb.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(rgb.count)).squareRoot()
    }

    private func render(_ amount: Double, sourceScale: Double = 1) -> CIImage {
        ImageAdjustmentRenderer.apply(.init(noiseReduction: amount), to: noisyGray, sourceScale: sourceScale)
    }

    @Test func moreAmountRemovesMoreNoise() throws {
        let source = noise(try pixels(noisyGray))
        let quarter = noise(try pixels(render(0.25)))
        let full = noise(try pixels(render(1)))

        #expect(quarter < source * 0.9)
        #expect(full < quarter * 0.9)
    }

    @Test func aDownsampledPreviewScalesTheAmountBySourceScale() throws {
        #expect(try pixels(render(0.8, sourceScale: 0.5)) == pixels(render(0.4)))
        #expect(try pixels(render(0.8, sourceScale: 2)) == pixels(render(0.8)))
    }

    /// The step must not clamp to 0…1, as Core Image's blend modes do: a Display P3 photo holds
    /// values outside it.
    @Test func wideGamutValuesPassThroughAFlatArea() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let color = try #require(CIColor(red: -0.1, green: 1.3, blue: 0.05, alpha: 1, colorSpace: space))
        let flat = CIImage(color: color).cropped(to: extent)

        let output = try pixels(ImageAdjustmentRenderer.apply(.init(noiseReduction: 1), to: flat))
        let center = (128 * 256 + 128) * 4

        #expect(abs(output[center] - -0.1) < 0.001)
        #expect(abs(output[center + 1] - 1.3) < 0.001)
        #expect(abs(output[center + 2] - 0.05) < 0.001)
    }
}
