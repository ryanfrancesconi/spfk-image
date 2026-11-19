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
    private let brighter = ImageAdjustmentDescription(light: .init(exposure: 1))

    // MARK: - Helpers

    private func convert(
        _ input: URL,
        named name: String,
        format: UTType = .png,
        adjustments: ImageAdjustmentDescription?,
        formats: ImageConversionFormats = ImageConversionFormats()
    ) async throws -> URL {
        let output = bin.appending(component: name, directoryHint: .notDirectory).appendingPathExtension("png")

        return try await ImageFormatConverter(
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

    @Test func adjustmentsReachTheOutputAndTheSourceIsUntouched() async throws {
        let input = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 6, in: bin)
        let before = try Data(contentsOf: input)

        let plain = try await convert(input, named: "plain", adjustments: nil)
        let adjusted = try await convert(input, named: "adjusted", adjustments: brighter)

        #expect(try meanLuminance(adjusted) > meanLuminance(plain) + 20)
        #expect(try Data(contentsOf: input) == before)
    }

    /// The encoder branch returns before a route is chosen, so the adjustments must not depend on one.
    @Test func adjustmentsReachAnEncoderOutput() async throws {
        let input = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 1, in: bin)
        let before = try Data(contentsOf: input)
        let formats = ImageConversionFormats(encoders: [ImageFormatConverterEncoderTests.PNGStandInEncoder()])

        let plain = try await convert(input, named: "plain", format: .webP, adjustments: nil, formats: formats)
        let adjusted = try await convert(input, named: "adjusted", format: .webP, adjustments: brighter, formats: formats)

        #expect(try meanLuminance(adjusted) > meanLuminance(plain) + 20)
        #expect(try Data(contentsOf: input) == before)
    }

    @Test func anAdjustedDisplayP3SourceStaysDisplayP3() async throws {
        let input = try displayP3PNG()
        try #require((try properties(input)[kCGImagePropertyProfileName as String] as? String)?.contains("P3") == true)

        let adjusted = try await convert(input, named: "adjusted", adjustments: brighter)

        #expect((try properties(adjusted)[kCGImagePropertyProfileName as String] as? String)?.contains("P3") == true)
    }

    @Test func neutralAdjustmentsCountAsNone() {
        let url = URL(fileURLWithPath: "/tmp/image.jpg")
        let source = ImageConversionSource(input: url, output: url, options: .init(), adjustments: ImageAdjustmentDescription())

        #expect(!source.hasAdjustments)
    }

    // MARK: - Crop

    private let crop = CropEdit(centerX: 0.1, centerY: -0.15, width: 0.5, height: 0.4, straighten: 7)

    private func convert(
        _ input: URL,
        format: UTType,
        crop: CropEdit,
        orientation: OrientationEdit = .up,
        maxPixelSize: Int? = nil,
        formats: ImageConversionFormats = ImageConversionFormats()
    ) async throws -> URL {
        let output = bin.appending(component: "cropped-\(UUID().uuidString)", directoryHint: .notDirectory).appendingPathExtension(for: format)

        return try await ImageFormatConverter(
            source: ImageConversionSource(
                input: input, output: output, options: ImageConversionOptions(format: format.identifier, maxPixelSize: maxPixelSize),
                orientation: orientation, crop: crop
            ),
            formats: formats
        ).convert().output
    }

    private func pixelSize(_ url: URL) throws -> (width: Int, height: Int) {
        let properties = try properties(url)
        return try (#require(properties[kCGImagePropertyPixelWidth as String] as? Int), #require(properties[kCGImagePropertyPixelHeight as String] as? Int))
    }

    @Test func aCropAloneTakesTheRenderRoute() {
        let url = URL(fileURLWithPath: "/tmp/image.jpg")
        let source = ImageConversionSource(input: url, output: url, options: .init(), crop: crop)

        #expect(source.rendersEdits)
        #expect(ImageFormatConverter.route(
            to: .heic, orientation: 1, colorModel: nil, resizes: false, adjusts: source.rendersEdits, metadata: .copyAll
        ) == .render)
    }

    @Test(arguments: [OrientationEdit.up, .right])
    func theOutputIsTheKeptSize(orientation: OrientationEdit) async throws {
        let input = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 6, in: bin)
        let upright = ImageFormatConverter.displayedSize(width: try pixelSize(input).width, height: try pixelSize(input).height, orientation: 6)
        let kept = crop.keptPixelSize(imageWidth: upright.width, imageHeight: upright.height)

        let output = try await convert(input, format: .png, crop: crop, orientation: orientation)
        let written = try pixelSize(output)

        #expect(written.width == (orientation.swapsDimensions ? kept.height : kept.width))
        #expect(written.height == (orientation.swapsDimensions ? kept.width : kept.height))
    }

    @Test func aCropWithAResizeKeepsTheKeptAspect() async throws {
        let input = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 1, in: bin)
        let size = try pixelSize(input)
        let kept = crop.keptPixelSize(imageWidth: size.width, imageHeight: size.height)

        let output = try await convert(input, format: .png, crop: crop, maxPixelSize: 200)
        let written = try pixelSize(output)
        let longest = max(kept.width, kept.height)

        #expect(max(written.width, written.height) == 200)
        #expect(abs(written.width - Int((Double(kept.width) * 200 / Double(longest)).rounded())) <= 1)
        #expect(abs(written.height - Int((Double(kept.height) * 200 / Double(longest)).rounded())) <= 1)
    }

    @Test func aCroppedHEICConversionCarriesItsGainMapCropped() async throws {
        guard #available(macOS 15, iOS 18, *) else { return }

        let bin = bin
        let input = try await BlockingCallLimiter.shared.run {
            try AdjustmentFileFixtures.checkerMapped(.heic, formats: [.iso], orientation: 6, in: bin)
        }
        let output = try await convert(input, format: .heic, crop: crop)

        let map = { (url: URL) throws -> (Int, Int) in
            let description = try #require(AdjustmentFileFixtures.GainMapFormat.iso.info(url)?[kCGImageAuxiliaryDataInfoDataDescription as String] as? [String: Any])
            return try (#require(description["Width"] as? Int), #require(description["Height"] as? Int))
        }

        // Drawn upright: the map is turned by the tag, then cropped as displayed.
        let source = try map(input)
        let expected = crop.keptPixelSize(imageWidth: source.1, imageHeight: source.0)
        let written = try map(output)

        #expect(written.0 == expected.width)
        #expect(written.1 == expected.height)
    }

    @Test func aCroppedEncoderOutputHasTheKeptSize() async throws {
        let input = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 1, in: bin)
        let size = try pixelSize(input)
        let kept = crop.keptPixelSize(imageWidth: size.width, imageHeight: size.height)
        let formats = ImageConversionFormats(encoders: [ImageFormatConverterEncoderTests.PNGStandInEncoder()])

        let output = try await convert(input, format: .webP, crop: crop, formats: formats)
        let written = try pixelSize(output)

        #expect(written.width == kept.width)
        #expect(written.height == kept.height)
    }
}
