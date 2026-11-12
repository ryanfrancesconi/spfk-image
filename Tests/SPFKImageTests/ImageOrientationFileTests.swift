// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import ImageIO
import SPFKBase
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

/// An orientation edit written to a file: by the lossless tag rewrite, and by Save's full render.
final class ImageOrientationFileTests {
    private let directory: URL
    private let renderer = ImageAdjustmentRenderer()

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spfk-image-orientation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Reading

    private func output(for source: URL) -> URL {
        directory.appendingPathComponent("rotated-\(source.lastPathComponent)")
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

    /// The decoded, unoriented bitmap.
    private func pixels(_ url: URL) throws -> Data {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try #require(image.dataProvider?.data as Data?)
    }

    private func gainMapData(_ url: URL) throws -> Data? {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) as? [String: Any]
        return info?[kCGImageAuxiliaryDataInfoData as String] as? Data
    }

    /// Whether the image and its gain map display with the same aspect, both oriented by the file's tag.
    private func gainMapDisplaysAlignedWithTheImage(_ url: URL) throws -> Bool {
        let image = try #require(CIImage(contentsOf: url, options: [.applyOrientationProperty: true]))
        let gainMap = try #require(CIImage(contentsOf: url, options: [.auxiliaryHDRGainMap: true, .applyOrientationProperty: true]))
        return (image.extent.width > image.extent.height) == (gainMap.extent.width > gainMap.extent.height)
    }

    // MARK: - Lossless rewrite

    @Test(arguments: [UTType.jpeg, .heic, .png, .tiff], [1, 6])
    func theRewriteChangesOnlyTheTag(type: UTType, start: Int) throws {
        try #require(OrientationEdit.losslessRewriteTypes.contains(type))
        let source = try AdjustmentFileFixtures.tagged(type, orientation: start, in: directory)
        let bytes = try Data(contentsOf: source)
        let output = output(for: source)

        try OrientationEdit.right.rewriteFile(source: source, destination: output)

        #expect(try orientation(output) == OrientationEdit.right.applied(toFileOrientation: start))
        #expect(try pixels(output) == pixels(source))
        #expect(try captureDate(output) == AdjustmentFileFixtures.captureDate)
        #expect(try latitude(output) == AdjustmentFileFixtures.latitude)
        #expect(try keywords(output) == AdjustmentFileFixtures.keywords)
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test(arguments: [UTType.jpeg, .heic])
    func theRewriteKeepsTheGainMap(type: UTType) throws {
        let source = try AdjustmentFileFixtures.gainMapped(type, in: directory)
        let original = try #require(try gainMapData(source))
        let output = output(for: source)

        try OrientationEdit.left.rewriteFile(source: source, destination: output)

        #expect(try orientation(output) == OrientationEdit.left.rawValue)
        #expect(try gainMapData(output) == original)
        #expect(try gainMapDisplaysAlignedWithTheImage(output))
    }

    @Test func aHEICNamedHEIFIsRewritten() throws {
        let heic = try AdjustmentFileFixtures.tagged(.heic, orientation: 1, in: directory)
        let source = directory.appendingPathComponent("named.heif")
        try FileManager.default.moveItem(at: heic, to: source)
        let reader = try #require(CGImageSourceCreateWithURL(source as CFURL, nil))
        try #require(CGImageSourceGetType(reader) as String? == UTType.heif.identifier)
        let output = output(for: source)

        try OrientationEdit.right.rewriteFile(source: source, destination: output)

        #expect(try orientation(output) == OrientationEdit.right.rawValue)
        #expect(try pixels(output) == pixels(source))
    }

    /// Pins why GIF is not in ``OrientationEdit/losslessRewriteTypes``.
    @Test func imageIORefusesToRewriteAGIF() throws {
        let source = try AdjustmentFileFixtures.tagged(.gif, orientation: 1, in: directory)
        let output = output(for: source)

        #expect(throws: ImageAdjustmentRenderError.encodeFailed) {
            try OrientationEdit.right.rewriteFile(source: source, destination: output)
        }

        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test func theRewriteLeavesAnExistingDestinationAlone() throws {
        let source = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 1, in: directory)
        let output = output(for: source)
        let occupant = Data("occupied".utf8)
        try occupant.write(to: output)

        #expect(throws: ImageAdjustmentRenderError.destinationExists) {
            try OrientationEdit.right.rewriteFile(source: source, destination: output)
        }

        #expect(try Data(contentsOf: output) == occupant)
    }

    // MARK: - Render with orientation

    @Test(arguments: [UTType.jpeg, .heic], [1, 6])
    func theRenderWritesTheComposedTag(type: UTType, start: Int) throws {
        let source = try AdjustmentFileFixtures.tagged(type, orientation: start, in: directory)
        let output = output(for: source)

        try renderer.renderFile(ImageAdjustmentDescription(light: .init(exposure: 1)), orientation: .flippedRight, source: source, destination: output)

        #expect(try orientation(output) == OrientationEdit.flippedRight.applied(toFileOrientation: start))
        #expect(try captureDate(output) == AdjustmentFileFixtures.captureDate)
    }

    @Test(arguments: [UTType.jpeg, .heic])
    func theRenderKeepsTheGainMapAligned(type: UTType) throws {
        let source = try AdjustmentFileFixtures.gainMapped(type, in: directory)
        let output = output(for: source)

        try renderer.renderFile(ImageAdjustmentDescription(light: .init(exposure: 1)), orientation: .right, source: source, destination: output)

        #expect(try orientation(output) == OrientationEdit.right.rawValue)
        #expect(try gainMapDisplaysAlignedWithTheImage(output))
    }
}

extension ImageOrientationFileTests {
    /// The 2×3 grid as a lossless file tagged `orientation`.
    private func gridFile(_ type: UTType, orientation: Int) throws -> URL {
        let url = directory.appendingPathComponent("grid-\(orientation)").appendingPathExtension(for: type)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        let image = try OrientationEditTests.image(OrientationEditTests.values)
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return url
    }

    private func displayedGrid(_ url: URL) throws -> OrientationEditTests.Grid {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3,
        ]
        return try OrientationEditTests.grid(try #require(CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)))
    }

    /// Export renders the edit on top of the file's own tag, whichever route the format would otherwise take.
    @Test(arguments: [UTType.png, .tiff], [OrientationEdit.right, .upMirrored, .leftMirrored])
    func anExportRendersTheEditOverTheFilesTag(format: UTType, edit: OrientationEdit) async throws {
        let source = try gridFile(.png, orientation: 6)
        let output = directory.appendingPathComponent("export-\(edit.rawValue)").appendingPathExtension(for: format)

        let written = try await ImageFormatConverter(
            source: ImageConversionSource(
                input: source,
                output: output,
                options: ImageConversionOptions(format: format.identifier),
                orientation: edit
            ),
            formats: ImageConversionFormats()
        ).convert().output

        #expect(try displayedGrid(written) == OrientationEditTests.displayed(
            OrientationEditTests.values, tag: edit.applied(toFileOrientation: 6)
        ))
    }
}

private extension OrientationEdit {
    /// Rotate Right then Flip Horizontal: a mirrored value, so a test sees both halves composed.
    static let flippedRight = OrientationEdit.up.rotatedRight.flippedHorizontally
}
