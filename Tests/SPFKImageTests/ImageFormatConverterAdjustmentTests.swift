// Copyright Ryan Francesconi. All Rights Reserved.

import CoreGraphics
import Foundation
import ImageIO
import SPFKBase
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

/// Pending adjustments rendered into a converted file, through ImageIO and through an ``ImageFileEncoder``.
@Suite(.tags(.file))
final class ImageFormatConverterAdjustmentTests: BinTestCase {
    private let brighter = ImageAdjustmentDescription(exposure: 1)

    // MARK: - Helpers

    private func convert(
        _ input: URL,
        named name: String,
        format: UTType = .png,
        adjustments: ImageAdjustmentDescription?,
        formats: ImageConversionFormats = ImageConversionFormats()
    ) throws -> URL {
        let output = bin.appending(component: name, directoryHint: .notDirectory).appendingPathExtension("png")

        return try ImageFormatConverter(
            source: ImageConversionSource(
                input: input,
                output: output,
                options: ImageConversionOptions(format: format.identifier),
                adjustments: adjustments
            ),
            formats: formats
        ).convert().output
    }

    private func meanLuminance(_ url: URL) throws -> Double {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try #require(ImageStatistics(image)).meanLuminance
    }

    private func properties(_ url: URL) throws -> [String: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }

    /// `songbird.jpg` drawn into Display P3 and written as PNG.
    private func displayP3PNG() throws -> URL {
        let songbird = try AdjustmentFileFixtures.songbird()
        let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))

        let context = try #require(CGContext(
            data: nil, width: songbird.width, height: songbird.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(songbird, in: CGRect(x: 0, y: 0, width: songbird.width, height: songbird.height))

        let url = bin.appending(component: "display-p3.png", directoryHint: .notDirectory)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        try #require(CGImageDestinationFinalize(destination))

        return url
    }

    // MARK: - Tests

    @Test func adjustmentsReachTheOutputAndTheSourceIsUntouched() throws {
        let input = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 6, in: bin)
        let before = try Data(contentsOf: input)

        let plain = try convert(input, named: "plain", adjustments: nil)
        let adjusted = try convert(input, named: "adjusted", adjustments: brighter)

        #expect(try meanLuminance(adjusted) > meanLuminance(plain) + 20)
        #expect(try Data(contentsOf: input) == before)
    }

    /// The encoder branch returns before a route is chosen, so the adjustments must not depend on one.
    @Test func adjustmentsReachAnEncoderOutput() throws {
        let input = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 1, in: bin)
        let before = try Data(contentsOf: input)
        let formats = ImageConversionFormats(encoders: [ImageFormatConverterEncoderTests.PNGStandInEncoder()])

        let plain = try convert(input, named: "plain", format: .webP, adjustments: nil, formats: formats)
        let adjusted = try convert(input, named: "adjusted", format: .webP, adjustments: brighter, formats: formats)

        #expect(try meanLuminance(adjusted) > meanLuminance(plain) + 20)
        #expect(try Data(contentsOf: input) == before)
    }

    @Test func anAdjustedDisplayP3SourceStaysDisplayP3() throws {
        let input = try displayP3PNG()
        try #require((try properties(input)[kCGImagePropertyProfileName as String] as? String)?.contains("P3") == true)

        let adjusted = try convert(input, named: "adjusted", adjustments: brighter)

        #expect((try properties(adjusted)[kCGImagePropertyProfileName as String] as? String)?.contains("P3") == true)
    }

    @Test func neutralAdjustmentsCountAsNone() {
        let url = URL(fileURLWithPath: "/tmp/image.jpg")
        let source = ImageConversionSource(input: url, output: url, options: .init(), adjustments: ImageAdjustmentDescription())

        #expect(!source.hasAdjustments)
    }
}
