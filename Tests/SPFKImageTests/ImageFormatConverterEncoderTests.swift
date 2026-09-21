// Copyright Ryan Francesconi. All Rights Reserved.

import CoreGraphics
import Foundation
import ImageIO
import SPFKBase
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

/// The converter's side of an ``ImageFileEncoder``: the types offered, the image and metadata handed over, and the size
/// refusal. ``PNGStandInEncoder`` claims WebP, which ImageIO reads and does not write.
@Suite(.tags(.file))
final class ImageFormatConverterEncoderTests: BinTestCase {
    /// Claims `type` and writes PNG, which ImageIO reads back whatever the type claimed.
    struct PNGStandInEncoder: ImageFileEncoder {
        var type: UTType = .webP
        var maxPixelSize: Int?

        /// Writes a 1×1 image whatever it is handed, as an encoder ignoring its input would.
        var writesOnePixel = false

        /// Cancels the task converting, as a Cancel pressed while the file is written does.
        var cancelsItsTask = false

        var usesQuality: Bool { false }

        func encode(_ input: ImageFileEncoderInput) throws -> Data {
            if cancelsItsTask {
                withUnsafeCurrentTask { $0?.cancel() }
            }

            let image = writesOnePixel ? try onePixel() : input.image
            let data = NSMutableData()

            guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
                throw ImageConversionError.encodeFailed(type.identifier)
            }

            CGImageDestinationAddImage(destination, image, nil)

            guard CGImageDestinationFinalize(destination) else { throw ImageConversionError.encodeFailed(type.identifier) }

            return data as Data
        }

        private func onePixel() throws -> CGImage {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  ),
                  let image = context.makeImage()
            else { throw ImageConversionError.encodeFailed(type.identifier) }

            return image
        }
    }

    // MARK: - Helpers

    private func requireWebPIsReadOnly() throws {
        try #require(ImageFormatConverter.readableTypeIdentifiers.contains(UTType.webP.identifier))
        try #require(!ImageFormatConverter.writableTypeIdentifiers.contains(UTType.webP.identifier))
    }

    private func convert(_ input: URL, named name: String, encoder: PNGStandInEncoder = .init(), maxPixelSize: Int? = nil) throws -> URL {
        let output = bin.appending(component: name, directoryHint: .notDirectory).appendingPathExtension("png")
        let options = ImageConversionOptions(format: UTType.webP.identifier, maxPixelSize: maxPixelSize)

        return try ImageFormatConverter(
            source: ImageConversionSource(input: input, output: output, options: options),
            formats: ImageConversionFormats(encoders: [encoder])
        ).convert().output
    }

    private func properties(_ url: URL) throws -> [String: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }

    private func pixelSize(_ properties: [String: Any]) throws -> ImageFormatConverter.PixelSize {
        try ImageFormatConverter.PixelSize(
            width: #require(properties[kCGImagePropertyPixelWidth as String] as? Int),
            height: #require(properties[kCGImagePropertyPixelHeight as String] as? Int)
        )
    }

    /// What ImageIO reads from `block` inside a JPEG's Exif segment.
    private func properties(ofEXIF block: Data) throws -> [String: Any] {
        let placeholder = ImageFormatConverter.placeholderJPEG
        let segment = jpegSegment(0xE1, Data("Exif".utf8) + Data([0, 0]) + block)
        let jpeg = placeholder.prefix(2) + segment + placeholder.dropFirst(2)

        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }

    private func jpegSegment(_ marker: UInt8, _ payload: Data) -> Data {
        let length = payload.count + 2
        return Data([0xFF, marker, UInt8(length >> 8), UInt8(length & 0xFF)]) + payload
    }

    private func metadata(
        _ scheme: ImageMetadataCopyScheme,
        of input: URL? = nil
    ) throws -> (exif: Data?, xmp: Data?, size: ImageFormatConverter.PixelSize) {
        let input = try input ?? AdjustmentFileFixtures.tagged(.jpeg, orientation: 6, in: bin)
        let source = try #require(CGImageSourceCreateWithURL(input as CFURL, nil))
        let size = ImageFormatConverter.PixelSize(width: 450, height: 800)

        let metadata = try ImageFormatConverter.encoderMetadata(source, index: 0, scheme: scheme, size: size, type: .webP)
        return (metadata.exif, metadata.xmp, size)
    }

    private func xmpPaths(_ xmpData: Data?) throws -> Set<String> {
        let data = try #require(xmpData)
        let xmp = try #require(CGImageMetadataCreateFromXMPData(data as CFData))
        var paths = Set<String>()

        CGImageMetadataEnumerateTagsUsingBlock(xmp, nil, nil) { _, tag in
            paths.insert("\(CGImageMetadataTagCopyPrefix(tag) as String? ?? ""):\(CGImageMetadataTagCopyName(tag) as String? ?? "")")
            return true
        }

        return paths
    }

    private func image(bytes: [UInt8], width: Int, bitsPerComponent: Int = 8, alpha: CGImageAlphaInfo) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))

        return try #require(CGImage(
            width: width, height: 1, bitsPerComponent: bitsPerComponent, bitsPerPixel: bitsPerComponent * 4,
            bytesPerRow: width * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    // MARK: - Formats

    @Test func anEncoderForATypeImageIOWritesOrAlreadyHasAnEncoderIsLeftOut() throws {
        try requireWebPIsReadOnly()

        let formats = ImageConversionFormats(encoders: [
            PNGStandInEncoder(type: .jpeg), PNGStandInEncoder(), PNGStandInEncoder(maxPixelSize: 10),
        ])

        #expect(formats.encoders.map(\.type.identifier) == [UTType.webP.identifier])
        #expect(formats.encoders.first?.maxPixelSize == nil)
    }

    @Test func anEncodersTypeIsOfferedAndKeepsMetadata() throws {
        try requireWebPIsReadOnly()

        let formats = ImageConversionFormats(encoders: [PNGStandInEncoder()])

        #expect(formats.outputTypes.contains(.webP))
        #expect(!ImageConversionFormats().outputTypes.contains(.webP))
        #expect(formats.carriesMetadata(.webP))
        #expect(!formats.usesQuality(.webP))
        #expect(formats.canWrite(.webP))
    }

    // MARK: - Conversion

    @Test func aRotatedSourceReachesTheEncoderUpright() throws {
        try requireWebPIsReadOnly()

        let input = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 6, in: bin)
        let stored = try pixelSize(properties(input))

        let output = try properties(convert(input, named: "upright"))

        #expect(try pixelSize(output) == .init(width: stored.height, height: stored.width))
        #expect(output[kCGImagePropertyOrientation as String] as? Int ?? 1 == 1)
    }

    @Test func anImageLargerThanTheEncoderHoldsIsRefusedUntilLimited() throws {
        try requireWebPIsReadOnly()

        let input = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 1, in: bin)
        let encoder = PNGStandInEncoder(maxPixelSize: 100)

        #expect(throws: ImageConversionError.exceedsMaxPixelSize(UTType.webP.identifier, 100)) {
            try self.convert(input, named: "refused", encoder: encoder)
        }

        let limited = try pixelSize(properties(convert(input, named: "limited", encoder: encoder, maxPixelSize: 100)))
        #expect(max(limited.width, limited.height) == 100)
    }

    /// An output that reads back at the wrong size never replaces the file already at its path.
    @Test func anEncoderWritingTheWrongSizeLeavesTheExistingOutput() throws {
        try requireWebPIsReadOnly()

        let input = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 1, in: bin)
        let output = bin.appending(component: "existing.png", directoryHint: .notDirectory)
        let existing = Data("existing".utf8)
        try existing.write(to: output)

        #expect(throws: ImageConversionError.readBackMismatch) {
            try self.convert(input, named: "existing", encoder: PNGStandInEncoder(writesOnePixel: true))
        }
        #expect(try Data(contentsOf: output) == existing)
    }

    /// A Cancel landing while the file is written leaves the file already at the output path.
    @Test func aCancelDuringTheWriteLeavesTheExistingOutput() async throws {
        try requireWebPIsReadOnly()

        let input = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 1, in: bin)
        let output = bin.appending(component: "existing.png", directoryHint: .notDirectory)
        let existing = Data("existing".utf8)
        try existing.write(to: output)

        let converter = ImageFormatConverter(
            source: ImageConversionSource(input: input, output: output, options: ImageConversionOptions(format: UTType.webP.identifier)),
            formats: ImageConversionFormats(encoders: [PNGStandInEncoder(cancelsItsTask: true)])
        )

        await #expect(throws: CancellationError.self) {
            try await Task { try converter.convert() }.value
        }
        #expect(try Data(contentsOf: output) == existing)
    }

    // MARK: - Metadata

    @Test func copyAllStatesOrientationOneAndTheOutputSize() throws {
        let metadata = try metadata(.copyAll)

        let exif = try properties(ofEXIF: #require(metadata.exif))
        let exifDictionary = exif[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let gps = exif[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]

        #expect(exif[kCGImagePropertyOrientation as String] as? Int == 1)
        #expect(exifDictionary[kCGImagePropertyExifPixelXDimension as String] as? Int == metadata.size.width)
        #expect(exifDictionary[kCGImagePropertyExifPixelYDimension as String] as? Int == metadata.size.height)
        #expect(exifDictionary[kCGImagePropertyExifDateTimeOriginal as String] as? String == AdjustmentFileFixtures.captureDate)
        #expect(abs((gps[kCGImagePropertyGPSLatitude as String] as? Double ?? 0) - AdjustmentFileFixtures.latitude) < 0.001)

        let xmpData = try #require(metadata.xmp)
        let xmp = try #require(CGImageMetadataCreateFromXMPData(xmpData as CFData))
        let paths = try xmpPaths(metadata.xmp)

        #expect(CGImageMetadataCopyStringValueWithPath(xmp, nil, "tiff:Orientation" as CFString) as String? == "1")
        #expect(paths.contains("dc:subject"))
        #expect(paths.contains { $0.hasPrefix("exif:GPS") })
    }

    @Test func copyAllHandsOverTorchTagsOwnFields() throws {
        let input = try ConversionFixtures.fields(orientation: 6, in: bin)
        let paths = try xmpPaths(metadata(.copyAll, of: input).xmp)

        #expect(paths.isSuperset(of: ["photoshop:LabelColor", "Iptc4xmpCore:AltTextAccessibility"]))
    }

    @Test func copyAllExceptLocationHandsOverNoLocation() throws {
        let metadata = try metadata(.copyAllExceptLocation)

        let exif = try properties(ofEXIF: #require(metadata.exif))
        let exifDictionary = exif[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let paths = try xmpPaths(metadata.xmp)

        #expect((exif[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]).isEmpty)
        #expect(exifDictionary[kCGImagePropertyExifDateTimeOriginal as String] as? String == AdjustmentFileFixtures.captureDate)
        #expect(!paths.contains { $0.contains(":GPS") })
        #expect(paths.contains("dc:subject"))
    }

    /// A location field in the `exifEX` namespace, which `exif:GPS` alone does not cover.
    @Test func copyAllExceptLocationHandsOverNoPositioningError() throws {
        let input = try ConversionFixtures.fields(orientation: 6, in: bin)
        try #require(xmpPaths(metadata(.copyAll, of: input).xmp).contains("exifEX:GPSHPositioningError"))

        let paths = try xmpPaths(metadata(.copyAllExceptLocation, of: input).xmp)

        #expect(!paths.contains { $0.contains(":GPS") })
        #expect(paths.contains("photoshop:LabelColor"))
    }

    @Test func stripAllHandsOverNoMetadata() throws {
        let metadata = try metadata(.stripAll)

        #expect(metadata.exif == nil)
        #expect(metadata.xmp == nil)
    }

    @Test func theEXIFBlockIsTheTIFFStructureAfterTheExifHeaderBeforeTheScan() {
        let start = Data([0xFF, 0xD8])
        let scan = Data([0xFF, 0xDA, 0x00, 0x02])
        let block = Data([0x4D, 0x4D, 0x00, 0x2A])

        let xmpFirst = start + jpegSegment(0xE1, Data("http://ns.adobe.com/xap/1.0/\0".utf8)) + jpegSegment(0xE1, Data("Exif".utf8) + Data([0, 0]) + block) + scan
        let afterScan = start + scan + jpegSegment(0xE1, Data("Exif".utf8) + Data([0, 0]) + block)

        #expect(ImageFormatConverter.exifPayload(ofJPEG: xmpFirst) == block)
        #expect(ImageFormatConverter.exifPayload(ofJPEG: afterScan) == nil)
        #expect(ImageFormatConverter.exifPayload(ofJPEG: Data("not a jpeg".utf8)) == nil)
    }

    // MARK: - Pixels

    @Test func pixelsWithAlphaAreUnpremultiplied() throws {
        // Premultiplied RGBA for a color of 204, 153, 102 at half opacity.
        let image = try image(bytes: [102, 77, 51, 128, 0, 0, 0, 0], width: 2, alpha: .premultipliedLast)

        let pixels = try ImageFileEncoderInput(image: image, quality: 1, exif: nil, xmp: nil).rgbaPixels(bitsPerComponent: 8)
        let first = [UInt8](pixels.data.prefix(4))

        #expect(pixels.hasAlpha)
        #expect(abs(Int(first[0]) - 203) <= 2)
        #expect(abs(Int(first[1]) - 153) <= 2)
        #expect(first[3] == 128)
    }

    @Test func sixteenBitSamplesHoldWhatEightBitSamplesDo() throws {
        let url = try AdjustmentFileFixtures.sixteenBit(.png, in: bin)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        try #require(image.bitsPerComponent == 16)

        let input = ImageFileEncoderInput(image: image, quality: 1, exif: nil, xmp: nil)
        let deep = try input.rgbaPixels(bitsPerComponent: 16)
        let shallow = try input.rgbaPixels(bitsPerComponent: 8)

        let deepRed = deep.data.withUnsafeBytes { Int($0.loadUnaligned(as: UInt16.self).littleEndian) }

        #expect(!deep.hasAlpha)
        #expect(deep.data.count == image.width * image.height * 8)
        #expect(abs(deepRed / 257 - Int(shallow.data[0])) <= 1)
    }

    @Test func aGrayImageIsGivenInSRGB() throws {
        let url = try AdjustmentFileFixtures.grayJPEG(in: bin)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        try #require(image.colorSpace?.model == .monochrome)

        let pixels = try ImageFileEncoderInput(image: image, quality: 1, exif: nil, xmp: nil).rgbaPixels(bitsPerComponent: 8)

        #expect(pixels.iccProfile == CGColorSpace(name: CGColorSpace.sRGB)?.copyICCData() as Data?)
    }
}
