// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SPFKTesting
import Testing
import simd

@testable import SPFKImage

@Suite(.tags(.file))
final class ImageAdjustmentSaturationTests {
    let context = CIContext()

    /// `colors`, encoded in `space`, rendered through Saturation `amount` as a one-row image, read back
    /// as unclamped linear sRGB.
    private func rendered(
        _ colors: [SIMD3<Double>],
        saturation amount: Double,
        space: CFString = CGColorSpace.sRGB
    ) throws -> [SIMD3<Double>] {
        let floats = colors.flatMap { color -> [Float] in [Float(color.x), Float(color.y), Float(color.z), 1] }
        let image = CIImage(
            bitmapData: floats.withUnsafeBufferPointer { Data(buffer: $0) },
            bytesPerRow: colors.count * 16,
            size: CGSize(width: colors.count, height: 1),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: space)
        )
        let adjusted = ImageAdjustmentRenderer.apply(.init(color: .init(saturation: amount)), to: image)
        let linear = try ImageAdjustmentChainPinTests.floatPixels(adjusted, context: context)

        return colors.indices.map { index in
            SIMD3(Double(linear[index * 4]), Double(linear[index * 4 + 1]), Double(linear[index * 4 + 2]))
        }
    }

    private static func linear(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(ImageAdjustmentRenderer.sRGBDecoded(rgb.x), ImageAdjustmentRenderer.sRGBDecoded(rgb.y), ImageAdjustmentRenderer.sRGBDecoded(rgb.z))
    }

    private static func chroma(_ linear: SIMD3<Double>) -> Double {
        let lab = ImageAdjustmentRenderer.oklab(linear: linear)
        return (lab.y * lab.y + lab.z * lab.z).squareRoot()
    }

    private static func hue(_ linear: SIMD3<Double>) -> Double {
        ImageAdjustmentRenderer.oklchHue(ImageAdjustmentRenderer.oklab(linear: linear))
    }

    private static func isInDisplayP3(_ linear: SIMD3<Double>) -> Bool {
        let p3 = ImageAdjustmentRenderer.linearSRGBToDisplayP3 * linear
        return p3.min() > -0.002 && p3.max() < 1.002
    }

    /// sRGB-encoded HSL hue sweeps, a degree apart.
    private static func sweep(saturation: Double, lightness: Double) -> [SIMD3<Double>] {
        (0 ..< 360).map { ImageAdjustmentRenderer.rgb(hue: Double($0), saturation: saturation, lightness: lightness) }
    }

    private static let primaries: [SIMD3<Double>] = [
        SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0), SIMD3(0, 1, 1), SIMD3(0, 0, 1), SIMD3(1, 0, 1),
    ]

    @Test func displayP3MatrixMatchesColorSync() throws {
        let source = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let target = try #require(CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3))

        for primary in Self.primaries {
            let color = try #require(CGColor(colorSpace: source, components: [primary.x, primary.y, primary.z, 1]))
            let converted = try #require(color.converted(to: target, intent: .relativeColorimetric, options: nil)?.components)
            let ours = ImageAdjustmentRenderer.linearSRGBToDisplayP3 * primary
            #expect(abs(ours.x - converted[0]) < 1e-6 && abs(ours.y - converted[1]) < 1e-6 && abs(ours.z - converted[2]) < 1e-6)
        }
    }

    /// At their own lightness and hue, sRGB's yellow and blue already lie on Display P3's edge.
    @Test func fullSaturationTakesThePrimariesBeyondSRGBAtTheirLightness() throws {
        let output = try rendered(Self.primaries, saturation: 1)
        let gains = zip(Self.primaries.map(Self.linear), output).map { Self.chroma($1) / Self.chroma($0) }

        for (input, saturated) in zip(Self.primaries.map(Self.linear), output) {
            #expect(abs(ImageAdjustmentRenderer.oklab(linear: saturated).x - ImageAdjustmentRenderer.oklab(linear: input).x) < 0.02)
            #expect(Self.isInDisplayP3(saturated))
        }
        #expect(gains.allSatisfy { $0 > 0.99 })
        #expect(gains[0] > 1.08 && gains[2] > 1.08)
    }

    @Test func dullColorsGainMoreThanVividOnes() throws {
        func meanGain(_ colors: [SIMD3<Double>]) throws -> Double {
            let output = try rendered(colors, saturation: 1)
            #expect(output.allSatisfy(Self.isInDisplayP3))
            return zip(colors.map(Self.linear), output).map { Self.chroma($1) / Self.chroma($0) }.reduce(0, +) / Double(colors.count)
        }

        let dull = try meanGain(Self.sweep(saturation: 0.1, lightness: 0.5))
        let vivid = try meanGain(Self.sweep(saturation: 1, lightness: 0.5))
        #expect(dull > 2.3)
        #expect(dull > vivid)
    }

    /// Near blue the colors that fit along a hue are not one interval from gray.
    @Test(arguments: [0.25, 0.5, 0.75, 1])
    func positiveSaturationNeverLosesChromaOrTurnsHue(amount: Double) throws {
        for colors in [Self.sweep(saturation: 1, lightness: 0.5), Self.sweep(saturation: 0.8, lightness: 0.3), Self.sweep(saturation: 0.8, lightness: 0.7)] {
            let output = try rendered(colors, saturation: amount)

            for (input, saturated) in zip(colors.map(Self.linear), output) {
                #expect(Self.chroma(saturated) > Self.chroma(input) - 0.01)
                #expect(abs(remainder(Self.hue(saturated) - Self.hue(input), 360)) < 2)
            }
        }
    }

    /// A color outside sRGB reaches the cube clamped to Display P3, not to sRGB, so its excess over
    /// sRGB is not added back on top of a saturated color.
    @Test func displayP3ColorsStayInsideDisplayP3() throws {
        let colors: [SIMD3<Double>] = [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(1, 0.5, 0), SIMD3(0.8, 0.3, 0.3)]
        let input = try rendered(colors, saturation: 0, space: CGColorSpace.displayP3)
        let output = try rendered(colors, saturation: 1, space: CGColorSpace.displayP3)

        for (original, saturated) in zip(input, output) {
            #expect(Self.isInDisplayP3(saturated))
            #expect(Self.chroma(saturated) > Self.chroma(original) - 0.01)
            #expect(abs(ImageAdjustmentRenderer.oklab(linear: saturated).x - ImageAdjustmentRenderer.oklab(linear: original).x) < 0.02)
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
        #expect(zip(colors.map(Self.linear), output).allSatisfy { input, unchanged in
            let difference = unchanged - input
            return max(difference.max(), -difference.min()) < 1e-5
        })
    }
}
