// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreGraphics
import CoreImage
import Foundation
@testable import SPFKImage
import Testing

@Suite("Color Grading")
struct ImageAdjustmentColorGradingTests {
    typealias Range = ImageAdjustmentDescription.ColorGradingRange

    // MARK: - Rendering helpers

    /// One pixel per color, 8-bit sRGB.
    private func strip(_ colors: [SIMD3<UInt8>]) throws -> CGImage {
        var bytes = [UInt8]()
        for color in colors {
            bytes += [color.x, color.y, color.z, 255]
        }

        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))

        return try #require(CGImage(
            width: colors.count, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: colors.count * 4,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    private func render(_ adjustments: ImageAdjustmentDescription, _ colors: [SIMD3<UInt8>]) throws -> [SIMD3<Int>] {
        let output = try #require(ImageAdjustmentRenderer().render(adjustments, source: try strip(colors)))
        let width = output.width
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(output, in: CGRect(x: 0, y: 0, width: width, height: 1))
        let data = try #require(context.data).bindMemory(to: UInt8.self, capacity: width * 4)

        return (0 ..< width).map { SIMD3(Int(data[$0 * 4]), Int(data[$0 * 4 + 1]), Int(data[$0 * 4 + 2])) }
    }

    private func luma(_ rgb: SIMD3<Double>) -> Double {
        (rgb * ImageAdjustmentRenderer.luminanceWeights).sum()
    }

    private func grading(
        shadows: (hue: Double, saturation: Double) = (0, 0),
        midtones: (hue: Double, saturation: Double) = (0, 0),
        highlights: (hue: Double, saturation: Double) = (0, 0),
        balance: Double = 0
    ) -> ImageAdjustmentDescription {
        ImageAdjustmentDescription(
            colorGrading: .init(
                shadows: .init(hue: shadows.hue, saturation: shadows.saturation),
                midtones: .init(hue: midtones.hue, saturation: midtones.saturation),
                highlights: .init(hue: highlights.hue, saturation: highlights.saturation),
                balance: balance
            )
        )
    }

    private static let grays: [SIMD3<UInt8>] = [0, 30, 64, 128, 192, 230, 255].map { SIMD3(repeating: $0) }
    private static let colors: [SIMD3<UInt8>] = grays + [SIMD3(200, 120, 40), SIMD3(30, 90, 160), SIMD3(255, 0, 0)]

    // MARK: - Tests

    @Test(arguments: [-1.0, 0, 1])
    func zeroSaturationIsIdentityWhateverTheHueAndBalance(balance: Double) throws {
        let adjustments = grading(shadows: (0.3, 0), midtones: (0.6, 0), highlights: (0.9, 0), balance: balance)

        #expect(!adjustments.colorGrading.hasTint)
        #expect(try render(adjustments, Self.colors) == render(ImageAdjustmentDescription(), Self.colors))
    }

    @Test func aShadowTintMovesADarkGrayTowardItsHueAndLeavesWhite() throws {
        let blue = 240.0 / 360
        let dark = SIMD3<UInt8>(repeating: 50)
        let white = SIMD3<UInt8>(repeating: 255)
        let pixels = try render(grading(shadows: (blue, 1)), [dark, white])

        #expect(pixels[0].z > pixels[0].x + 10)
        #expect(pixels[0].z > pixels[0].y + 10)
        #expect(pixels[1] == SIMD3(255, 255, 255))
    }

    @Test func aHighlightTintMovesALightGrayAndBarelyMovesADarkOne() throws {
        let orange = 30.0 / 360
        let pixels = try render(grading(highlights: (orange, 1)), [SIMD3(repeating: 40), SIMD3(repeating: 200)])
        let darkSpread = pixels[0].x - pixels[0].z
        let lightSpread = pixels[1].x - pixels[1].z

        #expect(lightSpread > 10)
        #expect(darkSpread < lightSpread / 4)
    }

    @Test(arguments: [0.0, 0.2, 0.45, 0.7, 0.95])
    func theTransformKeepsAGraysLuma(hue: Double) {
        let tints = Range.allCases.map { _ in ImageAdjustmentRenderer.colorGradingTint(hue: hue, saturation: 1) }

        for level in stride(from: 0.0, through: 1, by: 0.05) {
            for balance in [-1.0, 0, 1] {
                let gray = SIMD3<Double>(repeating: level)
                let output = ImageAdjustmentRenderer.colorGrading(gray, tints: tints, balance: balance)

                #expect(abs(luma(output) - level) < 1e-9)
                #expect(output.min() >= 0 && output.max() <= 1)
            }
        }
    }

    @Test(arguments: [0.0, 1.0 / 3, 2.0 / 3])
    func renderedGraysKeepTheirLuma(hue: Double) throws {
        let adjustments = grading(shadows: (hue, 1), midtones: (hue, 1), highlights: (hue, 1))
        let pixels = try render(adjustments, Self.grays)

        for (gray, pixel) in zip(Self.grays, pixels) {
            let input = luma(SIMD3<Double>(gray) / 255)
            let output = luma(SIMD3<Double>(pixel) / 255)
            #expect(abs(output - input) * 255 < 3, "gray \(gray.x) → \(pixel)")
        }
    }

    @Test func positiveBalanceExtendsTheHighlightTintIntoDarkerTones() throws {
        let orange = 30.0 / 360
        let gray = [SIMD3<UInt8>(repeating: 90)]
        let low = try render(grading(highlights: (orange, 1), balance: -1), gray)[0]
        let high = try render(grading(highlights: (orange, 1), balance: 1), gray)[0]

        #expect(high.x - high.z > low.x - low.z + 5)
    }

    @Test func theSameTintInEveryRangeIsUniform() {
        let tint = ImageAdjustmentRenderer.colorGradingTint(hue: 0.6, saturation: 0.5)
        let tints = [tint, tint, tint]

        for level in [0.3, 0.5, 0.7] {
            let gray = SIMD3<Double>(repeating: level)
            let output = ImageAdjustmentRenderer.colorGrading(gray, tints: tints, balance: 0.4)
            #expect(abs((output - gray - tint).max()) < 1e-9)
            #expect(abs((output - gray - tint).min()) < 1e-9)
        }
    }

    @Test func aBypassedRangeRendersUnchangedAndKeepsItsValue() throws {
        var adjustments = grading(shadows: (0.6, 0.8))
        adjustments.bypassed = [.colorGradingShadowSaturation]

        #expect(try render(adjustments, Self.colors) == render(ImageAdjustmentDescription(), Self.colors))
        #expect(adjustments.colorGrading.shadows.saturation == 0.8)
    }

    // MARK: - Storage

    @Test func colorGradingRoundTripsThroughCodable() throws {
        let adjustments = grading(shadows: (0.6, 0.4), midtones: (0.1, 0.2), highlights: (0.08, 0.9), balance: -0.3)
        let data = try JSONEncoder().encode(adjustments)

        #expect(try JSONDecoder().decode(ImageAdjustmentDescription.self, from: data) == adjustments)
    }
}
