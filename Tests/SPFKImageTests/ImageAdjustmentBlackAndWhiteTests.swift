// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreGraphics
import CoreImage
import Foundation
@testable import SPFKImage
import Testing

@Suite("Black & White")
struct ImageAdjustmentBlackAndWhiteTests {
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

    private static let red = SIMD3<UInt8>(255, 0, 0)
    private static let green = SIMD3<UInt8>(0, 255, 0)
    private static let colors: [SIMD3<UInt8>] = [
        red, green, SIMD3(0, 0, 255), SIMD3(200, 120, 40), SIMD3(30, 90, 160), SIMD3(255, 255, 255), SIMD3(0, 0, 0),
    ]

    // MARK: - Tests

    @Test(arguments: [-1.0, 0, 1])
    func fullAmountRendersEqualChannels(mix: Double) throws {
        let adjustments = ImageAdjustmentDescription(
            blackAndWhite: 1, blackAndWhiteRed: mix, blackAndWhiteGreen: -mix, blackAndWhiteBlue: mix / 2
        )

        for pixel in try render(adjustments, Self.colors) {
            #expect(max(abs(pixel.x - pixel.y), abs(pixel.y - pixel.z)) <= 1, "\(pixel)")
        }
    }

    @Test func zeroAmountIsIdentityWhateverTheMix() throws {
        let adjustments = ImageAdjustmentDescription(blackAndWhiteRed: 1, blackAndWhiteGreen: -1, blackAndWhiteBlue: 0.5)

        #expect(try render(adjustments, Self.colors) == render(ImageAdjustmentDescription(), Self.colors))
    }

    @Test(arguments: [-1.0, 1])
    func whiteAndBlackStayPutAtAnyMix(mix: Double) throws {
        let adjustments = ImageAdjustmentDescription(blackAndWhite: 1, blackAndWhiteRed: mix, blackAndWhiteGreen: mix)
        let pixels = try render(adjustments, [SIMD3(255, 255, 255), SIMD3(0, 0, 0)])

        #expect(pixels[0].x >= 254)
        #expect(pixels[1].x <= 1)
    }

    @Test func raisingRedBrightensRedRelativeToGreen() throws {
        let neutral = try render(ImageAdjustmentDescription(blackAndWhite: 1), [Self.red, Self.green])
        let raised = try render(ImageAdjustmentDescription(blackAndWhite: 1, blackAndWhiteRed: 1), [Self.red, Self.green])

        #expect(raised[0].x > neutral[0].x)
        #expect(raised[1].x < neutral[1].x)
    }

    @Test func partialAmountLiesBetweenColorAndMono() throws {
        let color = try render(ImageAdjustmentDescription(), [Self.red])[0]
        let mono = try render(ImageAdjustmentDescription(blackAndWhite: 1), [Self.red])[0]
        let half = try render(ImageAdjustmentDescription(blackAndWhite: 0.5), [Self.red])[0]

        #expect(half.x < color.x && half.x > mono.x)
        #expect(half.y > color.y && half.y < mono.y)
    }

    @Test func weightsSumToOneAndNeutralIsRec709() {
        let neutral = ImageAdjustmentRenderer.blackAndWhiteWeights(red: 0, green: 0, blue: 0)
        let skewed = ImageAdjustmentRenderer.blackAndWhiteWeights(red: 1, green: -1, blue: 0.3)

        #expect(abs(neutral.sum() - 1) < 1e-12)
        #expect(abs(skewed.sum() - 1) < 1e-12)
        #expect(abs(neutral.x - 0.2126) < 1e-4)
        #expect(skewed.x > neutral.x && skewed.y < neutral.y)
    }

    @Test func dataWrittenBeforeBlackAndWhiteDecodesAsNeutral() throws {
        let decoded = try JSONDecoder().decode(ImageAdjustmentDescription.self, from: Data(#"{"exposure":0.5}"#.utf8))

        #expect(decoded.blackAndWhite == 0)
        #expect(decoded.blackAndWhiteRed == 0)
    }

    @Test func blackAndWhiteRoundTripsThroughCodable() throws {
        let adjustments = ImageAdjustmentDescription(
            blackAndWhite: 0.7, blackAndWhiteRed: 0.4, blackAndWhiteGreen: -0.2, blackAndWhiteBlue: 1
        )
        let data = try JSONEncoder().encode(adjustments)

        #expect(try JSONDecoder().decode(ImageAdjustmentDescription.self, from: data) == adjustments)
    }
}
