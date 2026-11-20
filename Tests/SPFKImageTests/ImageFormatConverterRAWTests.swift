// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import ImageIO
import SPFKBase
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

/// Converting an adjusted RAW develops it, against real RAW files named by `SPFK_RAW_SAMPLES`.
@Suite(.tags(.file, .conversion), .serialized, .enabled(if: RAWSamples.folder != nil))
final class ImageFormatConverterRAWTests: BinTestCase {
    static let darker = ImageAdjustmentDescription(light: .init(exposure: -1.5))

    private func sample(_ name: String) throws -> URL {
        try #require(RAWSamples.url(name), "\(name) is not in the samples folder")
    }

    private func convert(
        _ input: URL,
        named name: String,
        adjustments: ImageAdjustmentDescription? = nil,
        crop: CropEdit = CropEdit()
    ) async throws -> URL {
        let source = ImageConversionSource(
            input: input,
            output: bin.appendingPathComponent(name).appendingPathExtension("heic"),
            options: ImageConversionOptions(format: UTType.heic.identifier),
            adjustments: adjustments,
            crop: crop
        )
        return try await ImageFormatConverter(source: source).convert().output
    }

    private func properties(_ url: URL) throws -> [String: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), nil) as? [String: Any])
    }

    /// The size `source` should write at, from its input's stored size and orientation tag.
    private func expectedSize(_ source: ImageConversionSource) throws -> ImageFormatConverter.PixelSize {
        let input = try properties(source.input)
        return try source.displayedSize(
            width: #require(input[kCGImagePropertyPixelWidth as String] as? Int),
            height: #require(input[kCGImagePropertyPixelHeight as String] as? Int),
            fileOrientation: input[kCGImagePropertyOrientation as String] as? Int ?? 1
        )
    }

    private func writtenSize(_ url: URL) throws -> ImageFormatConverter.PixelSize {
        let written = try properties(url)
        return try ImageFormatConverter.PixelSize(
            width: #require(written[kCGImagePropertyPixelWidth as String] as? Int),
            height: #require(written[kCGImagePropertyPixelHeight as String] as? Int)
        )
    }

    // MARK: - Develop

    @Test func convertDevelopsARAWWithAnAdjustment() async throws {
        let input = try sample("DSCF3303.RAF")

        let plain = try await convert(input, named: "plain")
        let darker = try await convert(input, named: "darker", adjustments: Self.darker)

        let source = ImageConversionSource(input: input, output: darker, options: ImageConversionOptions(), adjustments: Self.darker)
        #expect(try writtenSize(darker) == expectedSize(source))
        #expect(try properties(darker)[kCGImagePropertyOrientation as String] as? Int ?? 1 == 1)

        let plainClipped = try RAWMeasure(contentsOf: plain).clippedFraction
        let darkerClipped = try RAWMeasure(contentsOf: darker).clippedFraction
        print("DSCF3303 converted to HEIC, clipped at quarter scale: plain \(plainClipped), -1.5 EV \(darkerClipped)")

        #expect(darkerClipped < plainClipped / 2)
    }

    @Test func theCropFollowsTheDevelop() async throws {
        let input = try sample("DSCF3303.RAF")
        let leftHalf = CropEdit(centerX: -0.25, width: 0.5)

        let whole = try await convert(input, named: "whole", adjustments: Self.darker)
        let cropped = try await convert(input, named: "cropped", adjustments: Self.darker, crop: leftHalf)

        let source = ImageConversionSource(input: input, output: cropped, options: ImageConversionOptions(), adjustments: Self.darker, crop: leftHalf)
        let size = try writtenSize(cropped)
        #expect(try size == expectedSize(source))

        let croppedMeasure = try RAWMeasure(contentsOf: cropped)
        let wholeLeftMeasure = try RAWMeasure(contentsOf: whole, keepingLeftWidth: size.width)
        let difference = try #require(croppedMeasure.meanDifference(from: wholeLeftMeasure))

        #expect(difference < 0.01, "mean difference \(difference)")
    }

    // MARK: - Memory

    /// One at a time: a 24 MP develop's working set is near 2 GB, so a concurrent window, or a heavy suite
    /// running alongside, moves the footprint by hundreds of MB whether or not anything is kept. Holding the
    /// filter or its output keeps at least 96 MB a file, over 3 GB across the run.
    @Test(.tags(.slow)) func developingHoldsNoMemoryPerFile() async throws {
        let input = try sample("DSCF4449.RAF")
        let options = ImageConversionOptions(format: UTType.heic.identifier)
        let bin = bin

        let grown = try await retainedMemoryMB(warmUp: 4, measured: 32, width: 1) { index in
            let output = bin.appendingPathComponent("developed-\(index).heic")
            let source = ImageConversionSource(input: input, output: output, options: options, adjustments: Self.darker)
            _ = try await ImageFormatConverter(source: source).convert()
            try FileManager.default.removeItem(at: output)
        }

        print("DSCF4449 develop to HEIC grew \(grown) MB over 32 files")
        #expect(grown < 800, "grew \(Int(grown)) MB over 32 files")
    }
}

/// Writes the hand check's two files: Exposure -1.5 in the develop and after ImageIO's develop. Material
/// for a person to compare, not a test of behavior; skipped unless `SPFK_RAW_COMPARE_OUT` names a folder.
@Suite(.tags(.file), .enabled(if: RAWSamples.folder != nil && RAWComparisonFolder.url != nil))
struct RAWDevelopComparisonFiles {
    @Test func writeComparisonFiles() async throws {
        let input = try #require(RAWSamples.url("DSCF3303.RAF"))
        let folder = try #require(RAWComparisonFolder.url)

        let before = folder.appendingPathComponent("before-develop.heic")
        let after = folder.appendingPathComponent("after-develop.heic")

        for url in [before, after] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        _ = try await ImageFormatConverter(source: ImageConversionSource(
            input: input,
            output: before,
            options: ImageConversionOptions(format: UTType.heic.identifier),
            adjustments: ImageFormatConverterRAWTests.darker
        )).convert()

        let source = try #require(CGImageSourceCreateWithURL(input as CFURL, nil))
        let upright = CIImage(cgImageSource: source, index: CGImageSourceGetPrimaryImageIndex(source), options: [.applyOrientationProperty: true])
        let adjusted = ImageAdjustmentRenderer.apply(ImageFormatConverterRAWTests.darker, to: upright)
        let space = try #require(upright.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3))
        let image = try #require(CIContext().createCGImage(adjusted, from: adjusted.extent, format: .RGBA8, colorSpace: space))

        try await BlockingCallLimiter.shared.run {
            guard let destination = CGImageDestinationCreateWithURL(after as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
                throw ImageConversionError.unwritableType(UTType.heic.identifier)
            }
            let quality = [kCGImageDestinationLossyCompressionQuality: ImageConversionOptions().quality] as CFDictionary
            CGImageDestinationAddImage(destination, image, quality)
            guard CGImageDestinationFinalize(destination) else { throw ImageConversionError.encodeFailed(UTType.heic.identifier) }
        }

        #expect(FileManager.default.fileExists(atPath: before.path))
        #expect(FileManager.default.fileExists(atPath: after.path))
        print("RAW comparison files: \(before.path) and \(after.path)")
    }
}

enum RAWComparisonFolder {
    static var url: URL? {
        guard let path = ProcessInfo.processInfo.environment["SPFK_RAW_COMPARE_OUT"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
