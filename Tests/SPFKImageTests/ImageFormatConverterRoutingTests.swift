// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

/// Which path a conversion takes, the sizes it aims for, the offered types and the options' own rules.
struct ImageFormatConverterRoutingTests {
    private let rgb = kCGImagePropertyColorModelRGB as String

    private func route(
        _ identifier: String,
        orientation: Int = 1,
        colorModel: String? = nil,
        resizes: Bool = false,
        metadata: ImageMetadataCopyScheme = .copyAll
    ) throws -> ImageFormatConverter.Route {
        try ImageFormatConverter.route(
            to: #require(UTType(identifier)),
            orientation: orientation,
            colorModel: colorModel ?? rgb,
            resizes: resizes,
            metadata: metadata
        )
    }

    // MARK: - Route

    @Test(arguments: [UTType.jpeg.identifier, UTType.png.identifier, UTType.tiff.identifier])
    func aResizeIntoJPEGPNGOrTIFFRenders(identifier: String) throws {
        #expect(try route(identifier, resizes: true) == .render)
    }

    @Test func aResizeIntoHEICTranscodes() throws {
        #expect(try route(UTType.heic.identifier, resizes: true) == .transcode)
    }

    /// AVIF drops the orientation tag and refuses the metadata rewrite, so no scheme transcodes it.
    @Test(arguments: ImageMetadataCopyScheme.allCases)
    func anAVIFAlwaysRenders(metadata: ImageMetadataCopyScheme) throws {
        #expect(try route("public.avif", metadata: metadata) == .render)
    }

    /// GIF refuses the rewrite that restores what a transcode drops, so only a strip transcodes it.
    @Test func aGIFRendersUnlessItsMetadataIsStripped() throws {
        #expect(try route(UTType.gif.identifier, metadata: .copyAll) == .render)
        #expect(try route(UTType.gif.identifier, metadata: .copyAllExceptLocation) == .render)
        #expect(try route(UTType.gif.identifier, metadata: .stripAll) == .transcode)
    }

    /// A TIFF metadata rewrite loses the EXIF time zone offsets, so a TIFF keeping metadata is written from the decode.
    @Test func aTIFFKeepingMetadataIsRewrapped() throws {
        #expect(try route(UTType.tiff.identifier, metadata: .copyAll) == .rewrap)
        #expect(try route(UTType.tiff.identifier, metadata: .copyAllExceptLocation) == .rewrap)
        #expect(try route(UTType.tiff.identifier, metadata: .stripAll) == .transcode)
        #expect(try route(UTType.tiff.identifier, resizes: true) == .render)
    }

    @Test func aRotatedSourceIntoGIFRendersEvenWhenStripped() throws {
        #expect(try route(UTType.gif.identifier, orientation: 6, metadata: .stripAll) == .render)
    }

    @Test(arguments: [UTType.jpeg.identifier, UTType.heic.identifier, UTType.png.identifier])
    func aRotatedSourceIntoATaggedFormatTranscodes(identifier: String) throws {
        #expect(try route(identifier, orientation: 6) == .transcode)
    }

    @Test func aCMYKSourceRenders() throws {
        #expect(try route(UTType.jpeg.identifier, colorModel: kCGImagePropertyColorModelCMYK as String) == .render)
    }

    // MARK: - Sizes

    @Test(arguments: 1 ... 8)
    func theRotatingOrientationsSwapTheDisplayedSize(orientation: Int) {
        let size = ImageFormatConverter.displayedSize(width: 4, height: 3, orientation: orientation)
        let rotates = orientation >= 5

        #expect(size == .init(width: rotates ? 3 : 4, height: rotates ? 4 : 3))
    }

    @Test func aLimitScalesTheLongestEdgeAndNeverEnlarges() {
        #expect(ImageFormatConverter.limitedSize(.init(width: 1600, height: 900), maxPixelSize: 800) == .init(width: 800, height: 450))
        #expect(ImageFormatConverter.limitedSize(.init(width: 900, height: 1600), maxPixelSize: 800) == .init(width: 450, height: 800))
        #expect(ImageFormatConverter.limitedSize(.init(width: 1600, height: 900), maxPixelSize: 1600) == nil)
        #expect(ImageFormatConverter.limitedSize(.init(width: 1600, height: 900), maxPixelSize: nil) == nil)
    }

    // MARK: - Offered types

    @Test func theOfferedTypesIncludeThePhotoFormatsAndNoDocumentsTexturesOrIcons() {
        let identifiers = ImageConversionFormats().outputTypes.map(\.identifier)

        for required in [UTType.jpeg.identifier, UTType.heic.identifier, UTType.png.identifier, UTType.tiff.identifier, "public.avif"] {
            #expect(identifiers.contains(required), "\(required) is not offered")
        }

        for excluded in ["com.adobe.pdf", "com.microsoft.dds", "org.khronos.astc", "public.pvr", "com.apple.icns", "com.microsoft.ico"] {
            #expect(!identifiers.contains(excluded), "\(excluded) is offered")
        }
    }

    @Test func typesThatKeepMetadataAreOfferedFirst() {
        let formats = ImageConversionFormats()
        let keeps = formats.outputTypes.map(formats.carriesMetadata)

        #expect(keeps == keeps.sorted { $0 && !$1 })
    }

    // MARK: - Options

    @Test func optionsDecodeFromAnEmptyObjectToTheDefaults() throws {
        let decoded = try JSONDecoder().decode(ImageConversionOptions.self, from: Data("{}".utf8))

        #expect(decoded == ImageConversionOptions())
    }

    @Test func optionsRoundTripThroughJSON() throws {
        let options = ImageConversionOptions(
            format: UTType.png.identifier, quality: 0.4, maxPixelSize: 2048, conflictScheme: .unique, metadata: .copyAllExceptLocation
        )
        let decoded = try JSONDecoder().decode(ImageConversionOptions.self, from: JSONEncoder().encode(options))

        #expect(decoded == options)
    }

    @Test func qualityIsClampedAndANonFiniteValueFallsBackToTheDefault() {
        #expect(ImageConversionOptions(quality: 2).quality == 1)
        #expect(ImageConversionOptions(quality: -1).quality == 0)
        #expect(ImageConversionOptions(quality: .nan).quality == ImageAdjustmentRenderer.defaultFileQuality)

        var options = ImageConversionOptions()
        options.quality = 5
        #expect(options.quality == 1)
    }

    @Test func aNonPositiveMaxPixelSizeMeansTheSourceSize() {
        #expect(ImageConversionOptions(maxPixelSize: 0).maxPixelSize == nil)

        var options = ImageConversionOptions(maxPixelSize: 100)
        options.maxPixelSize = -5
        #expect(options.maxPixelSize == nil)
    }
}
