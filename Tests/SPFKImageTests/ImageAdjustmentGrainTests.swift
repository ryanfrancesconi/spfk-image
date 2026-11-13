// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreGraphics
import CoreImage
import Foundation
@testable import SPFKImage
import Testing

@Suite("Grain")
struct ImageAdjustmentGrainTests {
    // MARK: - Helpers

    /// A flat 8-bit sRGB gray.
    private func flat(_ level: UInt8, size: Int = 256) throws -> CGImage {
        let bytes = [UInt8](repeating: level, count: size * size * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))

        return try #require(CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    private func bytes(_ image: CGImage) throws -> [UInt8] {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data).bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        return Array(UnsafeBufferPointer(start: data, count: image.width * image.height * 4))
    }

    private func render(
        _ adjustments: ImageAdjustmentDescription,
        _ source: CGImage,
        sourceScale: Double = 1,
        crop: CGRect? = nil
    ) throws -> CGImage {
        try #require(ImageAdjustmentRenderer().render(adjustments, source: source, sourceScale: sourceScale, crop: crop))
    }

    // MARK: - Tests

    @Test func noAmountRendersNothingWhateverTheSize() throws {
        let source = try flat(128)
        let plain = try bytes(try render(ImageAdjustmentDescription(light: .init(exposure: 0.3)), source))
        let sized = try bytes(try render(ImageAdjustmentDescription(light: .init(exposure: 0.3), grain: .init(size: 1)), source))

        #expect(plain == sized)
    }

    @Test func theSameInputRendersTheSameGrainTwice() throws {
        let source = try flat(128)
        let adjustments = ImageAdjustmentDescription(grain: .init(amount: 1))

        #expect(try bytes(try render(adjustments, source)) == bytes(try render(adjustments, source)))
    }

    /// The zoomed preview renders a crop, which must show the full render's grain at that spot.
    @Test func aCropShowsTheFullRendersGrain() throws {
        let source = try flat(128)
        let adjustments = ImageAdjustmentDescription(grain: .init(amount: 1, size: 0.5))
        let full = try bytes(try render(adjustments, source))
        let crop = CGRect(x: 37, y: 101, width: 64, height: 48)
        let cropped = try bytes(try render(adjustments, source, crop: crop))

        var mismatches = 0
        for y in 0 ..< Int(crop.height) {
            for x in 0 ..< Int(crop.width) {
                let a = cropped[(y * Int(crop.width) + x) * 4]
                let b = full[((y + Int(crop.minY)) * 256 + x + Int(crop.minX)) * 4]
                if a != b { mismatches += 1 }
            }
        }

        #expect(mismatches == 0)
    }

    @Test(arguments: [UInt8(26), 64, 128, 192, 230])
    func grainKeepsEachGraysMeanAndAddsNoColor(level: UInt8) throws {
        let stats = try #require(ImageStatistics(try render(ImageAdjustmentDescription(grain: .init(amount: 1)), try flat(level))))

        #expect(abs(stats.meanLuminance - Double(level)) < 1)
        #expect(stats.luminanceStandardDeviation > 1)
        #expect(stats.meanChannelSpread == 0)
    }

    @Test(arguments: [UInt8(0), 255])
    func blackAndWhiteStayPure(level: UInt8) throws {
        let output = try bytes(try render(ImageAdjustmentDescription(grain: .init(amount: 1)), try flat(level)))

        #expect(output.enumerated().allSatisfy { $0.offset % 4 == 3 || $0.element == level })
    }

    @Test func midtonesTakeMoreGrainThanShadowsAndHighlights() throws {
        func deviation(_ level: UInt8) throws -> Double {
            try #require(ImageStatistics(try render(ImageAdjustmentDescription(grain: .init(amount: 1)), try flat(level))))
                .luminanceStandardDeviation
        }

        let mid = try deviation(128)
        #expect(try deviation(40) < mid)
        #expect(try deviation(215) < mid)
    }

    @Test func moreAmountIsStrongerGrain() throws {
        let source = try flat(128)
        let half = try #require(ImageStatistics(try render(ImageAdjustmentDescription(grain: .init(amount: 0.5)), source)))
        let full = try #require(ImageStatistics(try render(ImageAdjustmentDescription(grain: .init(amount: 1)), source)))

        #expect(full.luminanceStandardDeviation > half.luminanceStandardDeviation * 1.5)
    }

    /// Grain finer than a preview pixel averages out in the full render once downsampled.
    @Test func grainFinerThanAPreviewPixelIsWeaker() throws {
        let source = try flat(128)
        let adjustments = ImageAdjustmentDescription(grain: .init(amount: 1))
        let full = try #require(ImageStatistics(try render(adjustments, source)))
        let preview = try #require(ImageStatistics(try render(adjustments, source, sourceScale: 0.25)))

        #expect(preview.luminanceStandardDeviation < full.luminanceStandardDeviation * 0.75)
    }

    // MARK: - Seed

    private func render(_ adjustments: ImageAdjustmentDescription, _ source: CGImage, seed: Int64) throws -> CGImage {
        let image = CIImage(cgImage: source)
        let output = ImageAdjustmentRenderer.apply(adjustments, to: image, grainSeed: seed)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        return try #require(CIContext().createCGImage(output, from: image.extent, format: .RGBA8, colorSpace: space))
    }

    private func differingFraction(_ a: [UInt8], _ b: [UInt8]) -> Double {
        let differing = zip(a, b).enumerated().filter { $0.offset % 4 == 0 && $0.element.0 != $0.element.1 }.count
        return Double(differing) / Double(a.count / 4)
    }

    @Test func seedZeroIsTheImageGrain() throws {
        let source = try flat(128)
        let adjustments = ImageAdjustmentDescription(grain: .init(amount: 1))

        #expect(try bytes(try render(adjustments, source)) == bytes(try render(adjustments, source, seed: 0)))
    }

    @Test(arguments: [(Int64(0), Int64(1)), (1, 2), (2, 3), (1, 1000)])
    func differentSeedsGiveDifferentGrain(a: Int64, b: Int64) throws {
        let source = try flat(128)
        let adjustments = ImageAdjustmentDescription(grain: .init(amount: 1))
        let first = try bytes(try render(adjustments, source, seed: a))
        let second = try bytes(try render(adjustments, source, seed: b))

        #expect(differingFraction(first, second) > 0.5)
    }

    @Test func aSeedRepeats() throws {
        let source = try flat(128)
        let adjustments = ImageAdjustmentDescription(grain: .init(amount: 1, size: 0.5))

        #expect(try bytes(try render(adjustments, source, seed: 17)) == bytes(try render(adjustments, source, seed: 17)))
    }

    @Test func aSeedChangesThePatternNotTheStrength() throws {
        let source = try flat(128)
        let adjustments = ImageAdjustmentDescription(grain: .init(amount: 1))
        let unseeded = try #require(ImageStatistics(try render(adjustments, source, seed: 0)))
        let seeded = try #require(ImageStatistics(try render(adjustments, source, seed: 41)))

        #expect(abs(seeded.meanLuminance - unseeded.meanLuminance) < 1)
        #expect(abs(seeded.luminanceStandardDeviation / unseeded.luminanceStandardDeviation - 1) < 0.1)
    }

    @Test func grainRoundTripsThroughCodable() throws {
        let adjustments = ImageAdjustmentDescription(grain: .init(amount: 0.4, size: -0.5))
        let decoded = try JSONDecoder().decode(
            ImageAdjustmentDescription.self, from: try JSONEncoder().encode(adjustments)
        )

        #expect(decoded == adjustments)
    }
}
