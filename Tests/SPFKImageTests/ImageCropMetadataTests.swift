// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import ImageIO
import SPFKBase
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

/// Face regions (`mwg-rs:Regions`) moved with the pixels of a cropped or turned render.
@Suite(.tags(.file))
final class ImageCropMetadataTests {
    private let directory: URL
    private let renderer = ImageAdjustmentRenderer()

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spfk-image-crop-metadata-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private typealias Region = AdjustmentFileFixtures.Region

    // MARK: - ImageIO

    /// What the remap relies on: a value inside the structure changed by path and written back.
    @Test func theRegionStructureRoundTripsThroughImageIO() throws {
        let metadata = try AdjustmentFileFixtures.regionMetadata([Region(name: "a", x: 0.2, y: 0.3, w: 0.1, h: 0.1)])
        let path = "mwg-rs:Regions.mwg-rs:RegionList[0].mwg-rs:Area.stArea:x" as CFString

        #expect(CGImageMetadataSetValueWithPath(metadata, nil, path, "0.45" as CFString))

        let url = directory.appendingPathComponent("round-trip.jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImageAndMetadata(destination, try AdjustmentFileFixtures.asymmetricImage(), metadata, nil)
        try #require(CGImageDestinationFinalize(destination))

        let read = AdjustmentFileFixtures.regions(url)
        #expect(read.regions["a"]?.x == 0.45)
        #expect(read.regions["a"]?.y == 0.3)
        #expect(read.width == AdjustmentFileFixtures.asymmetricWidth)
    }

    // MARK: - The mapping

    private func remapped(_ regions: [Region], crop: CropEdit, written: (Int, Int)) throws -> (regions: [String: Region], width: Int?, height: Int?) {
        let metadata = try AdjustmentFileFixtures.regionMetadata(regions)

        ImageFormatConverter.remapRegions(
            metadata, storedWidth: 600, storedHeight: 400, before: .up, crop: crop, after: .up,
            writtenWidth: written.0, writtenHeight: written.1
        )

        return AdjustmentFileFixtures.regions(metadata)
    }

    @Test func aRegionInsideAQuarterCropDoublesFromItsCorner() throws {
        let crop = CropEdit(centerX: -0.25, centerY: -0.25, width: 0.5, height: 0.5)
        let result = try remapped(
            [Region(name: "in", x: 0.1, y: 0.2, w: 0.05, h: 0.1), Region(name: "out", x: 0.8, y: 0.8, w: 0.05, h: 0.1)],
            crop: crop, written: (300, 200)
        )
        let region = try #require(result.regions["in"])

        #expect(abs(region.x - 0.2) < 1e-9)
        #expect(abs(region.y - 0.4) < 1e-9)
        #expect(abs(region.w - 0.1) < 1e-9)
        #expect(abs(region.h - 0.2) < 1e-9)
        #expect(result.regions["out"] == nil)
        #expect(result.width == 300)
        #expect(result.height == 200)
    }

    @Test func noRegionLeftRemovesTheStructure() throws {
        let crop = CropEdit(centerX: -0.25, centerY: -0.25, width: 0.5, height: 0.5)
        let metadata = try AdjustmentFileFixtures.regionMetadata([Region(name: "out", x: 0.8, y: 0.8, w: 0.05, h: 0.1)])

        ImageFormatConverter.remapRegions(
            metadata, storedWidth: 600, storedHeight: 400, before: .up, crop: crop, after: .up, writtenWidth: 300, writtenHeight: 200
        )

        #expect(CGImageMetadataCopyTagWithPath(metadata, nil, "mwg-rs:Regions" as CFString) == nil)
    }

    // MARK: - Through Save and Convert Files

    /// The white mark's center in the upright decode, as fractions of it.
    private func markCenter(_ url: URL) throws -> SIMD2<Double> {
        let image = try #require(CIImage(contentsOf: url, options: [.applyOrientationProperty: true]))
        let cgImage = try #require(renderer.context.createCGImage(image, from: image.extent))
        let width = cgImage.width
        let height = cgImage.height
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        var sum = SIMD2<Double>(0, 0)
        var count = 0.0

        for y in 0 ..< height {
            for x in 0 ..< width {
                let index = (y * width + x) * 4
                guard pixels[index] > 240, pixels[index + 1] > 240, pixels[index + 2] > 240 else { continue }
                sum += SIMD2(Double(x) + 0.5, Double(y) + 0.5)
                count += 1
            }
        }

        try #require(count > 0, "no mark in \(url.lastPathComponent)")
        return SIMD2(sum.x / count / Double(width), sum.y / count / Double(height))
    }

    /// The mark region's center in `url`, as fractions of its upright picture.
    private func regionCenter(_ url: URL) throws -> SIMD2<Double> {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        let tag = OrientationEdit(rawValue: properties[kCGImagePropertyOrientation as String] as? Int ?? 1) ?? .up
        let region = try #require(AdjustmentFileFixtures.regions(url).regions["mark"])

        return tag.shownUnitPoint(forDisplayed: SIMD2(region.x, region.y))
    }

    /// A crop holding the mark, a little off its center.
    private func crop(around tag: OrientationEdit, straighten: Double) -> CropEdit {
        let mark = tag.shownUnitPoint(forDisplayed: SIMD2(AdjustmentFileFixtures.mark.x, AdjustmentFileFixtures.mark.y))
        return CropEdit(centerX: mark.x - 0.5 + 0.06, centerY: mark.y - 0.5 + 0.04, width: 0.45, height: 0.45, straighten: straighten)
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let tag: OrientationEdit
        let pending: OrientationEdit
        let straighten: Double

        var testDescription: String { "tag \(tag) pending \(pending) at \(straighten)" }
    }

    static let cases: [Case] = [
        Case(tag: .up, pending: .up, straighten: 0),
        Case(tag: .up, pending: .up, straighten: 10),
        Case(tag: .up, pending: .up, straighten: -10),
        Case(tag: .right, pending: .up, straighten: 10),
        Case(tag: .leftMirrored, pending: .up, straighten: 10),
        Case(tag: .right, pending: .upMirrored, straighten: -10),
        Case(tag: .down, pending: .left, straighten: 10),
    ]

    /// 1.5 % of the picture: the mark is 50 × 40 pixels and its centroid is rounded at the crop's edges.
    private static let tolerance = 0.015

    @Test(arguments: cases)
    func theRegionFollowsTheMarkThroughSave(item: Case) async throws {
        let source = try AdjustmentFileFixtures.asymmetric(.tiff, orientation: item.tag.rawValue, regions: [AdjustmentFileFixtures.mark], in: directory)
        let output = directory.appendingPathComponent("saved-\(UUID().uuidString).tiff")
        let crop = crop(around: item.tag, straighten: item.straighten)

        try await renderer.renderFile(ImageAdjustmentDescription(), orientation: item.pending, crop: crop, source: source, destination: output)

        let mark = try markCenter(output)
        let region = try regionCenter(output)

        #expect(abs(mark.x - region.x) < Self.tolerance && abs(mark.y - region.y) < Self.tolerance, "mark \(mark), region \(region)")
    }

    @Test(arguments: cases)
    func theRegionFollowsTheMarkThroughConvertFiles(item: Case) async throws {
        let source = try AdjustmentFileFixtures.asymmetric(.tiff, orientation: item.tag.rawValue, regions: [AdjustmentFileFixtures.mark], in: directory)
        let output = directory.appendingPathComponent("converted-\(UUID().uuidString).jpg")

        _ = try await ImageFormatConverter(source: ImageConversionSource(
            input: source, output: output, options: ImageConversionOptions(format: UTType.jpeg.identifier),
            orientation: item.pending, crop: crop(around: item.tag, straighten: item.straighten)
        )).convert()

        let mark = try markCenter(output)
        let region = try regionCenter(output)

        #expect(abs(mark.x - region.x) < Self.tolerance && abs(mark.y - region.y) < Self.tolerance, "mark \(mark), region \(region)")
    }

    /// A resize into JPEG is drawn upright and written as orientation 1, so a tagged file's regions turn too.
    @Test(arguments: [OrientationEdit.right, .leftMirrored, .down])
    func aRenderedConversionOfATaggedFileTurnsItsRegions(tag: OrientationEdit) async throws {
        let source = try AdjustmentFileFixtures.asymmetric(.tiff, orientation: tag.rawValue, regions: [AdjustmentFileFixtures.mark], in: directory)
        let output = directory.appendingPathComponent("converted-\(UUID().uuidString).jpg")

        _ = try await ImageFormatConverter(source: ImageConversionSource(
            input: source, output: output, options: ImageConversionOptions(format: UTType.jpeg.identifier, maxPixelSize: 300)
        )).convert()

        let mark = try markCenter(output)
        let region = try regionCenter(output)
        let applied = AdjustmentFileFixtures.regions(output)

        #expect(abs(mark.x - region.x) < Self.tolerance && abs(mark.y - region.y) < Self.tolerance, "mark \(mark), region \(region)")
        #expect(applied.width == (tag.swapsDimensions ? 200 : 300))
        #expect(applied.height == (tag.swapsDimensions ? 300 : 200))
    }
}
