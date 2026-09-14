// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import ImageIO
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

/// Save's render: adjusted pixels written in the source's format, keeping its metadata, orientation and
/// auxiliary images, and nothing left behind when it fails.
final class ImageAdjustmentFileRenderTests {
    private let directory: URL
    private let renderer = ImageAdjustmentRenderer()
    private let brighter = ImageAdjustmentDescription(exposure: 1)

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spfk-image-file-render-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Reading

    private func destination(for source: URL) -> URL {
        directory.appendingPathComponent("rendered-\(source.lastPathComponent)")
    }

    private func properties(_ url: URL) throws -> [String: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }

    private func orientation(_ url: URL) throws -> Int {
        try properties(url)[kCGImagePropertyOrientation as String] as? Int ?? 1
    }

    private func captureDate(_ url: URL) throws -> String? {
        (try properties(url)[kCGImagePropertyExifDictionary as String] as? [String: Any])?[kCGImagePropertyExifDateTimeOriginal as String] as? String
    }

    private func latitude(_ url: URL) throws -> Double? {
        (try properties(url)[kCGImagePropertyGPSDictionary as String] as? [String: Any])?[kCGImagePropertyGPSLatitude as String] as? Double
    }

    private func keywords(_ url: URL) throws -> [String] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))

        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "dc:subject" as CFString),
              let values = CGImageMetadataTagCopyValue(tag) as? [CGImageMetadataTag]
        else { return [] }

        return values.compactMap { CGImageMetadataTagCopyValue($0) as? String }.sorted()
    }

    private func hasGainMap(_ url: URL) throws -> Bool {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil
    }

    private func decode(_ url: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func meanLuminance(_ url: URL) throws -> Double {
        try #require(ImageStatistics(try decode(url))).meanLuminance
    }

    /// The size the file displays at, its orientation applied.
    private func uprightSize(_ url: URL) throws -> CGSize {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
        ]
        let thumbnail = try #require(CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary))
        return CGSize(width: thumbnail.width, height: thumbnail.height)
    }

    // MARK: - Fixtures

    @Test(arguments: [UTType.jpeg, .heic])
    func taggedFixturesCarryWhatTheTestsRelyOn(type: UTType) throws {
        let url = try AdjustmentFileFixtures.tagged(type, orientation: 6, in: directory)

        #expect(try orientation(url) == 6)
        #expect(try captureDate(url) == AdjustmentFileFixtures.captureDate)
        #expect(try latitude(url) == AdjustmentFileFixtures.latitude)
        #expect(try keywords(url) == AdjustmentFileFixtures.keywords)

        let size = try uprightSize(url)
        #expect(size.height > size.width, "orientation 6 should display songbird portrait")
    }

    @Test(arguments: [UTType.jpeg, .heic])
    func gainMapFixturesHaveAGainMap(type: UTType) throws {
        #expect(try hasGainMap(AdjustmentFileFixtures.gainMapped(type, in: directory)))
    }

    // MARK: - Pixels

    @Test func theAdjustmentIsInTheWrittenPixels() throws {
        let source = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 1, in: directory)
        let output = destination(for: source)

        try renderer.renderFile(brighter, source: source, destination: output)

        #expect(try meanLuminance(output) > meanLuminance(source) + 20)
    }

    @Test func transparencySurvives() throws {
        let source = try AdjustmentFileFixtures.halfTransparentPNG(in: directory)
        let output = destination(for: source)

        try renderer.renderFile(brighter, source: source, destination: output)

        let image = try decode(output)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))

        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }

        let row = image.height / 2
        let alpha = { (x: Int) in pixels[(row * image.width + x) * 4 + 3] }

        #expect(alpha(image.width / 8) == 255)
        #expect(alpha(image.width * 7 / 8) == 0)
    }

    @Test func grayscaleStaysGrayscale() throws {
        let source = try AdjustmentFileFixtures.grayJPEG(in: directory)
        let output = destination(for: source)

        try renderer.renderFile(brighter, source: source, destination: output)

        #expect(try properties(output)[kCGImagePropertyColorModel as String] as? String == kCGImagePropertyColorModelGray as String)
        #expect(try meanLuminance(output) > meanLuminance(source) + 20)
    }

    // MARK: - What the file keeps

    @Test(arguments: [UTType.jpeg, .heic])
    func metadataSurvives(type: UTType) throws {
        let source = try AdjustmentFileFixtures.tagged(type, orientation: 1, in: directory)
        let output = destination(for: source)

        try renderer.renderFile(brighter, source: source, destination: output)

        #expect(try captureDate(output) == AdjustmentFileFixtures.captureDate)
        #expect(try latitude(output) == AdjustmentFileFixtures.latitude)
        #expect(try keywords(output) == AdjustmentFileFixtures.keywords)
    }

    /// Catches the undocumented orientation option changing behavior: a HEIC written without it reads
    /// back as 1 and displays sideways.
    @Test(arguments: [UTType.jpeg, .heic], [6, 8])
    func orientationRoundTrips(type: UTType, orientation expected: Int) throws {
        let source = try AdjustmentFileFixtures.tagged(type, orientation: expected, in: directory)
        let output = destination(for: source)

        try renderer.renderFile(brighter, source: source, destination: output)

        #expect(try orientation(output) == expected)
        #expect(try uprightSize(output) == uprightSize(source))
    }

    @Test(arguments: [UTType.jpeg, .heic])
    func aGainMapIsCarried(type: UTType) throws {
        let source = try AdjustmentFileFixtures.gainMapped(type, in: directory)
        let output = destination(for: source)

        try renderer.renderFile(brighter, source: source, destination: output)

        #expect(try hasGainMap(output))
    }

    @Test func heicNamedHeifIsWritten() throws {
        let heic = try AdjustmentFileFixtures.tagged(.heic, orientation: 1, in: directory)
        let source = directory.appendingPathComponent("named.heif")
        try FileManager.default.moveItem(at: heic, to: source)

        let sourceRef = try #require(CGImageSourceCreateWithURL(source as CFURL, nil))
        try #require(CGImageSourceGetType(sourceRef) as String? == UTType.heif.identifier)

        let output = destination(for: source)
        try renderer.renderFile(brighter, source: source, destination: output)

        #expect(try meanLuminance(output) > meanLuminance(source) + 20)
    }

    // MARK: - Refusals

    /// The read-back check removes what it wrote and never touches the source.
    @Test func aReadBackMismatchLeavesNothingBehind() throws {
        let source = try AdjustmentFileFixtures.tagged(.heic, orientation: 6, in: directory)
        let bytes = try Data(contentsOf: source)
        let output = destination(for: source)

        #expect(throws: ImageAdjustmentRenderError.readBackMismatch) {
            try self.renderer.renderFile(self.brighter, source: source, destination: output, quality: 0.9, expectedOrientation: 1)
        }

        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test func aMultiPageFileIsRefused() throws {
        let source = try AdjustmentFileFixtures.twoPageTIFF(in: directory)
        let output = destination(for: source)

        #expect(throws: ImageAdjustmentRenderError.multipleImages) {
            try self.renderer.renderFile(self.brighter, source: source, destination: output)
        }

        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test func anExistingDestinationIsLeftAlone() throws {
        let source = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 1, in: directory)
        let output = destination(for: source)
        let occupant = Data("occupied".utf8)
        try occupant.write(to: output)

        #expect(throws: ImageAdjustmentRenderError.destinationExists) {
            try self.renderer.renderFile(self.brighter, source: source, destination: output)
        }

        #expect(try Data(contentsOf: output) == occupant)
    }
}
