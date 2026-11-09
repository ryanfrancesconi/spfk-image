// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreGraphics
import CoreImage
import Foundation
@testable import SPFKImage
import Testing

@Suite("Black & White")
struct ImageAdjustmentBlackAndWhiteTests {
    typealias Parameter = ImageAdjustmentDescription.Parameter

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
    private static let blue = SIMD3<UInt8>(0, 0, 255)
    private static let sky = SIMD3<UInt8>(90, 150, 220)
    private static let colors: [SIMD3<UInt8>] = [
        red, SIMD3(0, 255, 0), blue, sky, SIMD3(225, 170, 140), SIMD3(70, 120, 50), SIMD3(255, 255, 255), SIMD3(0, 0, 0),
    ]
    private static let grays: [SIMD3<UInt8>] = [0, 40, 128, 200, 255].map { SIMD3(repeating: $0) }

    private func everyBand(_ value: Double, amount: Double = 1) -> ImageAdjustmentDescription {
        var adjustments = ImageAdjustmentDescription(blackAndWhite: .init(amount: amount))
        for parameter in ImageAdjustmentDescription.ColorBand.allCases.map(\.blackAndWhite) {
            adjustments[parameter] = value
        }
        return adjustments
    }

    // MARK: - Tests

    @Test(arguments: [-1.0, 0, 1])
    func fullAmountRendersEqualChannels(value: Double) throws {
        for pixel in try render(everyBand(value), Self.colors) {
            #expect(max(abs(pixel.x - pixel.y), abs(pixel.y - pixel.z)) <= 1, "\(pixel)")
        }
    }

    @Test func zeroAmountIsIdentityWhateverTheBands() throws {
        #expect(try render(everyBand(1, amount: 0), Self.colors) == render(ImageAdjustmentDescription(), Self.colors))
    }

    @Test(arguments: [-1.0, 1])
    func graysTakeNoBandShift(value: Double) throws {
        let neutral = try render(everyBand(0), Self.grays)
        let shifted = try render(everyBand(value), Self.grays)

        for (a, b) in zip(neutral, shifted) {
            #expect(abs(a.x - b.x) <= 1, "\(a) \(b)")
        }
    }

    @Test func neutralBandsKeepEachColorsLuminance() throws {
        let rendered = try render(everyBand(0), Self.colors)

        for (color, pixel) in zip(Self.colors, rendered) {
            let srgb = SIMD3(Double(color.x), Double(color.y), Double(color.z)) / 255
            let linear = SIMD3(
                ImageAdjustmentRenderer.sRGBDecoded(srgb.x),
                ImageAdjustmentRenderer.sRGBDecoded(srgb.y),
                ImageAdjustmentRenderer.sRGBDecoded(srgb.z)
            )
            let expected = 255 * ImageAdjustmentRenderer.sRGBEncoded((linear * ImageAdjustmentRenderer.luminanceWeights).sum())
            #expect(abs(Double(pixel.x) - expected) <= 3, "\(color) → \(pixel.x), expected \(expected)")
        }
    }

    @Test func blueDownDarkensASkyAndLeavesRed() throws {
        let neutral = try render(everyBand(0), [Self.sky, Self.red])
        var adjustments = everyBand(0)
        adjustments.blackAndWhite.blue = -1
        let darkened = try render(adjustments, [Self.sky, Self.red])

        #expect(neutral[0].x - darkened[0].x >= 20, "\(neutral[0]) → \(darkened[0])")
        #expect(abs(neutral[1].x - darkened[1].x) <= 1)
    }

    @Test func redUpBrightensRedAndLeavesBlue() throws {
        let neutral = try render(everyBand(0), [Self.red, Self.blue])
        var adjustments = everyBand(0)
        adjustments.blackAndWhite.red = 1
        let raised = try render(adjustments, [Self.red, Self.blue])

        #expect(raised[0].x - neutral[0].x >= 40, "\(neutral[0]) → \(raised[0])")
        #expect(abs(raised[1].x - neutral[1].x) <= 1)
    }

    @Test func partialAmountLiesBetweenColorAndMono() throws {
        let color = try render(ImageAdjustmentDescription(), [Self.red])[0]
        let mono = try render(ImageAdjustmentDescription(blackAndWhite: .init(amount: 1)), [Self.red])[0]
        let half = try render(ImageAdjustmentDescription(blackAndWhite: .init(amount: 0.5)), [Self.red])[0]

        #expect(half.x < color.x && half.x > mono.x)
        #expect(half.y > color.y && half.y < mono.y)
    }

    @Test func eachBandOwnsADistinctParameter() {
        #expect(Set(ImageAdjustmentDescription.ColorBand.allCases.map(\.blackAndWhite)).count == ImageAdjustmentDescription.ColorBand.allCases.count)
        #expect(ImageAdjustmentDescription.ColorBand.allCases.map(\.blackAndWhite).allSatisfy { $0.range == -1 ... 1 })
    }

    @Test func blackAndWhiteRoundTripsThroughCodable() throws {
        let adjustments = ImageAdjustmentDescription(
            blackAndWhite: .init(amount: 0.7, red: 0.4, yellow: -0.1, cyan: -0.2, magenta: 1)
        )
        let data = try JSONEncoder().encode(adjustments)

        #expect(try JSONDecoder().decode(ImageAdjustmentDescription.self, from: data) == adjustments)
    }
}
