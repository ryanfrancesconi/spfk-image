// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import ImageIO
import SPFKBase
import SPFKFileSystem
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

/// An XMP packet laid over the copied metadata, as a camera RAW's sidecar is, on every route a converter takes.
@Suite(.tags(.file, .conversion, .xmpSidecar))
final class ImageFormatConverterOverlayTests: BinTestCase {
    private static func packet(_ body: String) -> String {
        """
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\
        <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/">\(body)</rdf:Description></rdf:RDF></x:xmpmeta>
        """
    }

    private static let keywordOverlay = packet(
        "<dc:subject><rdf:Bag><rdf:li>sidecar</rdf:li></rdf:Bag></dc:subject><photoshop:City>Paris</photoshop:City>"
    )

    private static let clearingOverlay = packet("<dc:subject><rdf:Bag/></dc:subject>")

    private func convert(_ input: URL, to identifier: String, _ scheme: ImageMetadataCopyScheme, overlay: String?) async throws -> URL {
        let type = try #require(UTType(identifier))
        let output = bin.appending(component: "overlay-\(scheme.rawValue)", directoryHint: .notDirectory).appendingPathExtension(for: type)
        let options = ImageConversionOptions(format: identifier, conflictScheme: .overwrite, metadata: scheme)

        return try await ImageFormatConverter(
            source: ImageConversionSource(input: input, output: output, options: options, overlayXMP: overlay)
        ).convert().output
    }

    private func metadata(of url: URL) throws -> CGImageMetadata? {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return CGImageSourceCopyMetadataAtIndex(source, 0, nil)
    }

    /// `dc:subject`'s items; nil when the property is absent.
    private static func keywords(in metadata: CGImageMetadata?) -> [String]? {
        guard let metadata,
              let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "dc:subject" as CFString),
              let items = CGImageMetadataTagCopyValue(tag) as? [AnyObject]
        else { return nil }

        return items.compactMap { item in
            if let string = item as? String { return string }
            guard CFGetTypeID(item) == CGImageMetadataTagGetTypeID() else { return nil }
            return CGImageMetadataTagCopyValue(unsafeDowncast(item, to: CGImageMetadataTag.self)) as? String
        }
    }

    private static func city(in metadata: CGImageMetadata?) -> String? {
        metadata.flatMap { CGImageMetadataCopyStringValueWithPath($0, nil, "photoshop:City" as CFString) as String? }
    }

    private func source() throws -> URL {
        let url = try ConversionFixtures.fields(orientation: 1, in: bin)
        try #require(Self.keywords(in: metadata(of: url)) == AdjustmentFileFixtures.keywords)
        return url
    }

    @Test(arguments: ImageFormatConverterMetadataTests.keepingTypes)
    func anOverlayReplacesAndAddsProperties(identifier: String) async throws {
        let output = try await convert(source(), to: identifier, .copyAll, overlay: Self.keywordOverlay)
        let written = try metadata(of: output)

        #expect(Self.keywords(in: written) == ["sidecar"])
        #expect(Self.city(in: written) == "Paris")
        #expect(written.flatMap { CGImageMetadataCopyStringValueWithPath($0, nil, "photoshop:LabelColor" as CFString) as String? }
            == ConversionFixtures.labelColor)
    }

    @Test(arguments: ImageFormatConverterMetadataTests.keepingTypes)
    func anEmptyArrayInTheOverlayClearsTheSourcesOwn(identifier: String) async throws {
        let output = try await convert(source(), to: identifier, .copyAll, overlay: Self.clearingOverlay)

        #expect(Self.keywords(in: try metadata(of: output)) ?? [] == [])
    }

    @Test func stripAllStripsTheOverlay() async throws {
        let output = try await convert(source(), to: UTType.jpeg.identifier, .stripAll, overlay: Self.keywordOverlay)
        let written = try metadata(of: output)

        #expect(Self.keywords(in: written) == nil)
        #expect(Self.city(in: written) == nil)
    }

    /// The path an ``ImageFileEncoder`` is given its metadata through.
    @Test func theEncoderMetadataCarriesTheOverlay() throws {
        let url = try source()
        let imageSource = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let overlay = try #require(CGImageMetadataCreateFromXMPData(Data(Self.keywordOverlay.utf8) as CFData))

        let encoded = try ImageFormatConverter.encoderMetadata(
            imageSource, index: 0, scheme: .copyAll, size: .init(width: 4, height: 4), type: .jpeg, overlay: overlay
        )
        let xmp = try #require(encoded.xmp)
        let written = CGImageMetadataCreateFromXMPData(xmp as CFData)

        #expect(Self.keywords(in: written) == ["sidecar"])
        #expect(Self.city(in: written) == "Paris")
    }

    @Test func anOverlayThatIsNotXMPFailsTheConversion() async throws {
        await #expect(throws: ImageConversionError.unreadableOverlayXMP) {
            try await self.convert(self.source(), to: UTType.jpeg.identifier, .copyAll, overlay: "not xmp")
        }
    }
}
