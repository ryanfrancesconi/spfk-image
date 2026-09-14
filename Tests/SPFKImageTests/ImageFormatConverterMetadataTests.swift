// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import ImageIO
import SPFKBase
import SPFKFileSystem
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

/// What each metadata scheme keeps, read back through ImageIO, and the gain map carried with it.
@Suite(.tags(.file))
final class ImageFormatConverterMetadataTests: BinTestCase {
    /// Every type that keeps metadata. AVIF, and GIF while metadata is kept, reach the render path.
    static let keepingTypes = [
        UTType.jpeg.identifier, UTType.heic.identifier, UTType.png.identifier, UTType.tiff.identifier,
        "com.adobe.photoshop-image", "public.avif", UTType.gif.identifier,
    ]

    private struct ReadBack {
        let properties: [String: Any]
        let paths: Set<String>

        var exif: [String: Any] { properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:] }
        var gps: [String: Any] { properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:] }
        var orientation: Int { properties[kCGImagePropertyOrientation as String] as? Int ?? 1 }

        var displayedSize: ImageFormatConverter.PixelSize {
            ImageFormatConverter.displayedSize(
                width: properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0,
                height: properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0,
                orientation: orientation
            )
        }

        var hasLocationInXMP: Bool {
            paths.contains { $0.hasPrefix("exif:GPS") || $0.hasPrefix("exifEX:GPS") }
        }
    }

    private func readBack(_ url: URL) throws -> ReadBack {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        var paths = Set<String>()

        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { _, tag in
                let prefix = CGImageMetadataTagCopyPrefix(tag) as String? ?? ""
                let name = CGImageMetadataTagCopyName(tag) as String? ?? ""
                paths.insert("\(prefix):\(name)")
                return true
            }
        }

        return ReadBack(properties: properties, paths: paths)
    }

    private func convert(
        _ input: URL,
        to identifier: String,
        _ metadata: ImageMetadataCopyScheme,
        maxPixelSize: Int? = nil,
        conflictScheme: FileConflictScheme = .overwrite
    ) throws -> URL {
        let type = try #require(UTType(identifier))
        let output = bin.appending(component: "\(metadata.rawValue)-\(maxPixelSize ?? 0)", directoryHint: .notDirectory)
            .appendingPathExtension(for: type)

        let options = ImageConversionOptions(
            format: identifier, maxPixelSize: maxPixelSize, conflictScheme: conflictScheme, metadata: metadata
        )

        return try ImageFormatConverter(
            source: ImageConversionSource(input: input, output: output, options: options)
        ).convert().output
    }

    /// A rotated source with every field, the fields and its Finder tags asserted before use.
    private func taggedSource() throws -> (url: URL, readBack: ReadBack) {
        let url = try ConversionFixtures.fields(orientation: 6, in: bin)
        try url.set(tagNames: ConversionFixtures.finderTags)

        let source = try readBack(url)
        try #require(source.exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String == ConversionFixtures.timeZoneOffset)
        try #require(source.gps.isNotEmpty)
        try #require(source.paths.isSuperset(of: ["dc:subject", "photoshop:LabelColor", "Iptc4xmpCore:AltTextAccessibility"]))
        try #require(Set(url.tagNames) == Set(ConversionFixtures.finderTags))

        return (url, source)
    }

    // MARK: - Schemes

    @Test(arguments: keepingTypes)
    func copyAllKeepsEveryField(identifier: String) throws {
        let source = try taggedSource()
        let output = try convert(source.url, to: identifier, .copyAll)
        let written = try readBack(output)

        #expect(written.displayedSize == source.readBack.displayedSize)
        #expect(written.exif[kCGImagePropertyExifDateTimeOriginal as String] as? String == AdjustmentFileFixtures.captureDate)
        #expect(written.gps.isNotEmpty)
        #expect(written.paths.isSuperset(of: ["dc:subject", "photoshop:LabelColor", "Iptc4xmpCore:AltTextAccessibility"]))
        #expect(Set(output.tagNames) == Set(ConversionFixtures.finderTags))

        // PSD holds XMP only through a metadata rewrite, and that rewrite drops the offsets.
        if identifier != "com.adobe.photoshop-image" {
            #expect(written.exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String == ConversionFixtures.timeZoneOffset)
        }
    }

    @Test(arguments: keepingTypes)
    func copyAllExceptLocationRemovesOnlyTheLocation(identifier: String) throws {
        let source = try taggedSource()
        let output = try convert(source.url, to: identifier, .copyAllExceptLocation)
        let written = try readBack(output)

        #expect(written.gps.isEmpty)
        #expect(!written.hasLocationInXMP)
        #expect(written.exif[kCGImagePropertyExifDateTimeOriginal as String] as? String == AdjustmentFileFixtures.captureDate)
        #expect(written.paths.isSuperset(of: ["dc:subject", "photoshop:LabelColor", "Iptc4xmpCore:AltTextAccessibility"]))
        #expect(Set(output.tagNames) == Set(ConversionFixtures.finderTags))
    }

    @Test(arguments: keepingTypes)
    func stripAllKeepsOnlyTheImage(identifier: String) throws {
        let source = try taggedSource()
        let output = try convert(source.url, to: identifier, .stripAll)
        let written = try readBack(output)

        #expect(written.displayedSize == source.readBack.displayedSize)
        #expect(written.exif[kCGImagePropertyExifDateTimeOriginal as String] == nil)
        #expect(written.gps.isEmpty)
        #expect(!written.hasLocationInXMP)
        #expect(written.paths.isDisjoint(with: ["dc:subject", "photoshop:LabelColor", "Iptc4xmpCore:AltTextAccessibility"]))
        #expect(output.tagNames.isEmpty)
    }

    /// A resize into JPEG goes through the render path, which must honor the scheme as the transcode does.
    @Test(arguments: ImageMetadataCopyScheme.allCases)
    func aResizedJPEGHonorsTheScheme(metadata: ImageMetadataCopyScheme) throws {
        let source = try taggedSource()
        let written = try readBack(convert(source.url, to: UTType.jpeg.identifier, metadata, maxPixelSize: 400))

        #expect(written.paths.contains("photoshop:LabelColor") == (metadata != .stripAll))
        #expect(written.gps.isEmpty == (metadata != .copyAll))
    }

    /// The replaced file's own tags are not carried into its replacement.
    @Test func replacingATaggedOutputUnderStripAllLeavesNoTags() throws {
        let source = try taggedSource()
        let first = try convert(source.url, to: UTType.heic.identifier, .copyAll)
        try #require(first.tagNames.isNotEmpty)

        let stripped = bin.appending(component: "\(ImageMetadataCopyScheme.stripAll.rawValue)-0", directoryHint: .notDirectory)
            .appendingPathExtension(for: .heic)
        try FileManager.default.copyItem(at: first, to: stripped)
        try #require(stripped.tagNames.isNotEmpty)

        let output = try convert(source.url, to: UTType.heic.identifier, .stripAll)

        #expect(output == stripped)
        #expect(output.tagNames.isEmpty)
    }

    @Test func anUnreadableSourceIsRefusedWithAReason() throws {
        let input = bin.appending(component: "broken.jpg", directoryHint: .notDirectory)
        try Data("not an image".utf8).write(to: input)

        #expect(throws: ImageConversionError.unreadable(input)) {
            try self.convert(input, to: UTType.heic.identifier, .copyAll)
        }
    }

    // MARK: - Gain maps

    @Test(arguments: [UTType.jpeg.identifier, UTType.heic.identifier, "public.avif"])
    func stripAllKeepsTheGainMap(identifier: String) throws {
        let input = try AdjustmentFileFixtures.gainMapped(.heic, in: bin)
        let output = try convert(input, to: identifier, .stripAll)
        let written = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))

        #expect(CGImageSourceCopyAuxiliaryDataInfoAtIndex(written, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil)
    }

    @Test func aResizedJPEGKeepsItsGainMap() throws {
        let input = try AdjustmentFileFixtures.gainMapped(.jpeg, in: bin)
        let output = try convert(input, to: UTType.jpeg.identifier, .copyAll, maxPixelSize: 400)
        let written = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))

        #expect(CGImageSourceCopyAuxiliaryDataInfoAtIndex(written, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil)
    }

    /// AVIF renders upright, so a rotated source's gain map has to turn with its pixels or it lights the wrong areas.
    @Test func aRotatedGainMapTurnsWithTheImage() throws {
        let input = try ConversionFixtures.rotatedGainMap(orientation: 6, in: bin)
        let source = try #require(CGImageSourceCreateWithURL(input as CFURL, nil))
        let sourceMap = try #require(
            CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) as? [String: Any]
        )
        let sourceDescription = try #require(sourceMap[kCGImageAuxiliaryDataInfoDataDescription as String] as? [String: Any])
        let sourceWidth = try #require(sourceDescription["Width"] as? Int)
        let sourceHeight = try #require(sourceDescription["Height"] as? Int)
        try #require(sourceWidth != sourceHeight)

        let output = try convert(input, to: "public.avif", .copyAll)
        let written = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        let writtenMap = try #require(
            CGImageSourceCopyAuxiliaryDataInfoAtIndex(written, 0, kCGImageAuxiliaryDataTypeHDRGainMap) as? [String: Any]
        )
        let writtenDescription = try #require(writtenMap[kCGImageAuxiliaryDataInfoDataDescription as String] as? [String: Any])

        #expect(try readBack(output).orientation == 1)
        #expect(writtenDescription["Width"] as? Int == sourceHeight)
        #expect(writtenDescription["Height"] as? Int == sourceWidth)
    }
}
