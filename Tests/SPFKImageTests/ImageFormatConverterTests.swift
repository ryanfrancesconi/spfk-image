// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import ImageIO
import SPFKBase
import SPFKFileSystem
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

/// One file converted and read back through ImageIO. Sources come from ``AdjustmentFileFixtures``.
@Suite(.tags(.file))
final class ImageFormatConverterTests: BinTestCase {
    // MARK: - Helpers

    private func output(_ name: String, _ type: UTType, in directory: URL? = nil) -> URL {
        (directory ?? bin).appending(component: name, directoryHint: .notDirectory).appendingPathExtension(for: type)
    }

    private func directory(_ name: String) throws -> URL {
        let url = bin.appending(component: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func source() throws -> URL {
        try AdjustmentFileFixtures.tagged(.jpeg, orientation: 1, in: bin)
    }

    @discardableResult
    private func convert(
        _ input: URL,
        to output: URL,
        _ options: ImageConversionOptions,
        originalInput: URL? = nil
    ) throws -> ImageConversionSource {
        try ImageFormatConverter(
            source: ImageConversionSource(input: input, output: output, options: options, originalInput: originalInput)
        ).convert()
    }

    private func properties(_ url: URL) throws -> [String: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }

    private func displayedSize(_ url: URL) throws -> ImageFormatConverter.PixelSize {
        let properties = try properties(url)

        return try ImageFormatConverter.displayedSize(
            width: #require(properties[kCGImagePropertyPixelWidth as String] as? Int),
            height: #require(properties[kCGImagePropertyPixelHeight as String] as? Int),
            orientation: properties[kCGImagePropertyOrientation as String] as? Int ?? 1
        )
    }

    private func fileSize(_ url: URL) throws -> Int {
        try #require(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }

    // MARK: - Formats

    @Test(arguments: ImageConversionFormats().outputTypes)
    func everyOfferedTypeConvertsAtTheSourceSize(type: UTType) throws {
        let input = try source()
        let expected = try displayedSize(input)

        let converted = try convert(input, to: output("converted", type), ImageConversionOptions(format: type.identifier))

        #expect(try displayedSize(converted.output) == expected)
    }

    @Test(arguments: [UTType.jpeg.identifier, UTType.heic.identifier, UTType.png.identifier, UTType.tiff.identifier, "public.avif"])
    func maxPixelSizeCapsTheLongestEdge(identifier: String) throws {
        let type = try #require(UTType(identifier))
        let input = try source()
        let sourceSize = try displayedSize(input)
        let limit = max(sourceSize.width, sourceSize.height) / 2

        let converted = try convert(input, to: output("resized", type), ImageConversionOptions(format: identifier, maxPixelSize: limit))
        let size = try displayedSize(converted.output)

        #expect(max(size.width, size.height) == limit)
        #expect(abs(min(size.width, size.height) - min(sourceSize.width, sourceSize.height) / 2) <= 1)
        #expect(try properties(converted.output)[kCGImagePropertyHasAlpha as String] as? Bool != true)
    }

    @Test func aSourceWithinTheLimitIsNotEnlarged() throws {
        let input = try source()
        let sourceSize = try displayedSize(input)
        let limit = max(sourceSize.width, sourceSize.height) * 2

        let converted = try convert(input, to: output("kept", .jpeg), ImageConversionOptions(maxPixelSize: limit))

        #expect(try displayedSize(converted.output) == sourceSize)
    }

    @Test(arguments: ImageFormatConverter.lossyTypeIdentifiers.sorted().filter { ImageFormatConverter.writableTypeIdentifiers.contains($0) })
    func lowerQualityWritesASmallerFile(identifier: String) throws {
        let type = try #require(UTType(identifier))
        let input = try source()

        let low = try convert(input, to: output("low", type), ImageConversionOptions(format: identifier, quality: 0.1))
        let high = try convert(input, to: output("high", type), ImageConversionOptions(format: identifier, quality: 0.9))

        #expect(try fileSize(low.output) < fileSize(high.output))
    }

    @Test func resizingIntoJPEGKeepsTheCaptureDateAndLocation() throws {
        let input = try source()
        let sourceEXIF = try #require(properties(input)[kCGImagePropertyExifDictionary as String] as? [String: Any])
        try #require(sourceEXIF[kCGImagePropertyExifDateTimeOriginal as String] as? String == AdjustmentFileFixtures.captureDate)

        let converted = try convert(input, to: output("resized", .jpeg), ImageConversionOptions(maxPixelSize: 400))
        let written = try properties(converted.output)

        let exif = try #require(written[kCGImagePropertyExifDictionary as String] as? [String: Any])
        #expect(exif[kCGImagePropertyExifDateTimeOriginal as String] as? String == AdjustmentFileFixtures.captureDate)

        let gps = try #require(written[kCGImagePropertyGPSDictionary as String] as? [String: Any])
        let latitude = try #require(gps[kCGImagePropertyGPSLatitude as String] as? Double)
        #expect(abs(latitude - AdjustmentFileFixtures.latitude) < 0.001)
    }

    @Test(arguments: ["public.avif", UTType.gif.identifier, UTType.jpeg.identifier, UTType.heic.identifier])
    func aRotatedSourceDisplaysUpright(identifier: String) throws {
        let type = try #require(UTType(identifier))
        let input = try AdjustmentFileFixtures.tagged(.heic, orientation: 6, in: bin)
        let expected = try displayedSize(input)
        try #require(expected.width < expected.height)

        let converted = try convert(input, to: output("upright", type), ImageConversionOptions(format: identifier))

        #expect(try displayedSize(converted.output) == expected)
    }

    @Test func aCMYKSourceIsWrittenAsRGB() throws {
        let input = try AdjustmentFileFixtures.cmykTIFF(in: bin)
        try #require(properties(input)[kCGImagePropertyColorModel as String] as? String == kCGImagePropertyColorModelCMYK as String)

        let converted = try convert(input, to: output("rgb", .jpeg), ImageConversionOptions())

        #expect(try properties(converted.output)[kCGImagePropertyColorModel as String] as? String == kCGImagePropertyColorModelRGB as String)
    }

    /// ImageIO cannot copy a HEIC into a HEIF sequence, so this one converts through the renderer.
    @Test func aHEICSourceConvertsToAHEIFSequence() throws {
        let identifier = "public.heics"
        try #require(ImageFormatConverter.writableTypeIdentifiers.contains(identifier))

        let input = try AdjustmentFileFixtures.tagged(.heic, orientation: 1, in: bin)
        let converted = try convert(input, to: output("sequence", #require(UTType(identifier))), ImageConversionOptions(format: identifier))

        #expect(try displayedSize(converted.output) == displayedSize(input))
    }

    @Test func aGainMapIsCarriedIntoHEIC() throws {
        let input = try AdjustmentFileFixtures.gainMapped(.heic, in: bin)
        let sourceImage = try #require(CGImageSourceCreateWithURL(input as CFURL, nil))
        try #require(CGImageSourceCopyAuxiliaryDataInfoAtIndex(sourceImage, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil)

        let converted = try convert(input, to: output("carried", .heic), ImageConversionOptions(format: UTType.heic.identifier))
        let written = try #require(CGImageSourceCreateWithURL(converted.output as CFURL, nil))

        #expect(CGImageSourceCopyAuxiliaryDataInfoAtIndex(written, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil)
    }

    // MARK: - Conflicts

    @Test func theErrorSchemeLeavesAnExistingOutputAlone() throws {
        let input = try source()
        let existing = output("existing", .heic)
        try Data("existing".utf8).write(to: existing)

        #expect(throws: ImageConversionError.outputExists(existing)) {
            try self.convert(input, to: existing, ImageConversionOptions(format: UTType.heic.identifier, conflictScheme: .error))
        }

        #expect(try Data(contentsOf: existing) == Data("existing".utf8))
    }

    @Test func theOverwriteSchemeReplacesAnExistingOutput() throws {
        let input = try source()
        let existing = output("existing", .heic)
        try Data("existing".utf8).write(to: existing)

        let converted = try convert(input, to: existing, ImageConversionOptions(format: UTType.heic.identifier, conflictScheme: .overwrite))

        #expect(converted.output == existing)
        #expect(try displayedSize(existing) == displayedSize(input))
    }

    @Test func theUniqueSchemeWritesBesideAnExistingOutput() throws {
        let input = try source()
        let existing = output("existing", .heic)
        try Data("existing".utf8).write(to: existing)

        let converted = try convert(input, to: existing, ImageConversionOptions(format: UTType.heic.identifier, conflictScheme: .unique))

        #expect(converted.output.lastPathComponent == "existing_1.heic")
        #expect(try displayedSize(converted.output) == displayedSize(input))
        #expect(try Data(contentsOf: existing) == Data("existing".utf8))
    }

    // MARK: - The source is never written

    @Test(arguments: FileConflictScheme.allCases)
    func refusesAnOutputThatIsItsOwnInput(scheme: FileConflictScheme) throws {
        let input = try source()
        let before = try Data(contentsOf: input)

        #expect(throws: ImageConversionError.outputReplacesInput(input)) {
            try self.convert(input, to: input, ImageConversionOptions(conflictScheme: scheme))
        }

        #expect(try Data(contentsOf: input) == before)
    }

    @Test func refusesAnOutputReachedThroughASymlinkedDirectory() throws {
        let real = try directory("real")
        let input = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 1, in: real)
        let before = try Data(contentsOf: input)

        let alias = bin.appending(component: "alias", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        let output = alias.appending(component: input.lastPathComponent, directoryHint: .notDirectory)

        #expect(throws: ImageConversionError.outputReplacesInput(input)) {
            try self.convert(input, to: output, ImageConversionOptions())
        }

        #expect(try Data(contentsOf: input) == before)
    }

    @Test func refusesAnOutputThatIsTheFileARenderStandsIn() throws {
        let original = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 1, in: directory("original"))
        let render = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 3, in: directory("render"))
        let before = try Data(contentsOf: original)

        #expect(throws: ImageConversionError.outputReplacesInput(original)) {
            try self.convert(render, to: original, ImageConversionOptions(), originalInput: original)
        }

        #expect(try Data(contentsOf: original) == before)
    }

    // MARK: - Cancellation

    @Test func aCancelledConversionLeavesNoOutput() async throws {
        let input = try source()
        let output = output("cancelled", .heic)
        let converter = ImageFormatConverter(
            source: ImageConversionSource(input: input, output: output, options: ImageConversionOptions(format: UTType.heic.identifier))
        )

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try converter.convert()
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        #expect(!output.exists)
        #expect(try FileManager.default.contentsOfDirectory(atPath: bin.path) == [input.lastPathComponent])
    }
}
