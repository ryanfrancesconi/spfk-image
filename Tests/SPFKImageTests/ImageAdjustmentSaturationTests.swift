// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SPFKTesting
import Testing

@testable import SPFKImage

@Suite(.tags(.file))
final class ImageAdjustmentSaturationTests {
    let context = CIContext()

    /// sRGB-encoded `colors` rendered through Saturation `amount` as a one-row image, read back
    /// sRGB-encoded and unclamped.
    private func rendered(_ colors: [SIMD3<Double>], saturation amount: Double) throws -> [SIMD3<Double>] {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let floats = colors.flatMap { color -> [Float] in [Float(color.x), Float(color.y), Float(color.z), 1] }
        let image = CIImage(
            bitmapData: floats.withUnsafeBufferPointer { Data(buffer: $0) },
            bytesPerRow: colors.count * 16,
            size: CGSize(width: colors.count, height: 1),
            format: .RGBAf,
            colorSpace: space
        )
        let adjusted = ImageAdjustmentRenderer.apply(.init(color: .init(saturation: amount)), to: image)
        let linear = try ImageAdjustmentChainPinTests.floatPixels(adjusted, context: context)

        return colors.indices.map { index in
            let pixel = linear[index * 4 ..< index * 4 + 3].map { ImageAdjustmentRenderer.sRGBEncoded(Double($0)) }
            return SIMD3(pixel[0], pixel[1], pixel[2])
        }
    }

    private static func chroma(_ rgb: SIMD3<Double>) -> Double {
        let lab = ImageAdjustmentRenderer.oklab(rgb)
        return (lab.y * lab.y + lab.z * lab.z).squareRoot()
    }

    private static func sweep(saturation: Double, lightness: Double) -> [SIMD3<Double>] {
        (0 ..< 360).map { ImageAdjustmentRenderer.rgb(hue: Double($0), saturation: saturation, lightness: lightness) }
    }

    private static func isInGamut(_ rgb: SIMD3<Double>) -> Bool {
        rgb.min() > -0.002 && rgb.max() < 1.002
    }

    @Test func fullSaturationHoldsThePrimariesLightness() throws {
        let primaries: [SIMD3<Double>] = [
            SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0), SIMD3(0, 1, 1), SIMD3(0, 0, 1), SIMD3(1, 0, 1),
        ]
        let output = try rendered(primaries, saturation: 1)

        for (input, saturated) in zip(primaries, output) {
            #expect(abs(ImageAdjustmentRenderer.oklab(saturated).x - ImageAdjustmentRenderer.oklab(input).x) < 0.02)
            #expect(Self.isInGamut(saturated))
        }
    }

    @Test func dullColorsGainMoreThanVividOnes() throws {
        func meanGain(_ colors: [SIMD3<Double>]) throws -> Double {
            let output = try rendered(colors, saturation: 1)
            #expect(output.allSatisfy(Self.isInGamut))
            return zip(colors, output).map { Self.chroma($1) / Self.chroma($0) }.reduce(0, +) / Double(colors.count)
        }

        let dull = try meanGain(Self.sweep(saturation: 0.25, lightness: 0.5))
        let vivid = try meanGain(Self.sweep(saturation: 1, lightness: 0.5))
        #expect(dull > 1.5)
        #expect(dull > vivid)
    }

    /// Near blue the colors that fit sRGB along one hue are not one interval from gray.
    @Test(arguments: [0.25, 0.5, 0.75, 1])
    func positiveSaturationNeverLosesChromaOrTurnsHue(amount: Double) throws {
        for colors in [Self.sweep(saturation: 1, lightness: 0.5), Self.sweep(saturation: 0.8, lightness: 0.3), Self.sweep(saturation: 0.8, lightness: 0.7)] {
            let output = try rendered(colors, saturation: amount)

            for (input, saturated) in zip(colors, output) {
                #expect(Self.chroma(saturated) > Self.chroma(input) - 0.01)
                let turn = remainder(
                    ImageAdjustmentRenderer.oklchHue(ImageAdjustmentRenderer.oklab(saturated))
                        - ImageAdjustmentRenderer.oklchHue(ImageAdjustmentRenderer.oklab(input)),
                    360
                )
                #expect(abs(turn) < 2)
            }
        }
    }

    @Test func negativeSaturationIsCoreImagesFilter() throws {
        let input = CIImage(cgImage: try CGImage.contentsOf(url: TestBundleResources.shared.songbird))
        let filter = CIFilter.colorControls()
        filter.inputImage = input
        filter.saturation = 0.4
        let reference = try ImageAdjustmentChainPinTests.floatPixels(try #require(filter.outputImage).cropped(to: input.extent), context: context)
        let ours = try ImageAdjustmentChainPinTests.floatPixels(
            ImageAdjustmentRenderer.apply(.init(color: .init(saturation: -0.6)), to: input), context: context
        )

        #expect(zip(reference, ours).map { abs($0 - $1) }.max() == 0)
    }

    @Test func zeroSaturationLeavesColorsUnchanged() throws {
        let colors = Self.sweep(saturation: 0.5, lightness: 0.5)
        let output = try rendered(colors, saturation: 0)
        #expect(zip(colors, output).allSatisfy { input, unchanged in
            let difference = unchanged - input
            return max(difference.max(), -difference.min()) < 1e-5
        })
    }
}
