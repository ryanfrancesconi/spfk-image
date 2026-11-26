// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import ImageIO
import SPFKBase
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

/// Save's crop: the gain maps cropped with the pixels, the rest of the auxiliary images dropped, and the
/// EXIF size stating what was written.
@Suite(.tags(.file))
final class ImageAdjustmentFileCropTests {
    private let directory: URL
    private let renderer = ImageAdjustmentRenderer()
    private let crop = CropEdit(centerX: 0.1, centerY: -0.15, width: 0.5, height: 0.4, straighten: 7)
    private let corrected = CropEdit(centerX: 0.1, centerY: -0.15, width: 0.5, height: 0.4, straighten: 7, vertical: 10, horizontal: -6)

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spfk-image-file-crop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func destination(_ source: URL) -> URL {
        directory.appendingPathComponent("cropped-\(UUID().uuidString)").appendingPathExtension(source.pathExtension)
    }

    private func properties(_ url: URL) throws -> [String: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }

    private func mapSize(_ info: [String: Any]?) throws -> (width: Int, height: Int) {
        let description = try #require(info?[kCGImageAuxiliaryDataInfoDataDescription as String] as? [String: Any])
        return try (#require(description["Width"] as? Int), #require(description["Height"] as? Int))
    }

    // MARK: - HDR

    @available(macOS 15, iOS 18, *)
    private func hdr(_ image: CIImage, width: Int, height: Int) throws -> [Float] {
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3))
        var pixels = [Float](repeating: 0, count: width * height * 4)

        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            renderer.context.render(
                image, toBitmap: base, rowBytes: width * 16,
                bounds: CGRect(x: image.extent.minX, y: image.extent.minY, width: CGFloat(width), height: CGFloat(height)),
                format: .RGBAf, colorSpace: space
            )
        }

        return pixels
    }

    @available(macOS 15, iOS 18, *)
    private func hdrDecode(_ url: URL) throws -> CIImage {
        try #require(CIImage(contentsOf: url, options: [.expandToHDR: true, .applyOrientationProperty: true]))
    }

    /// Mean absolute difference per channel, extended linear Display P3.
    @available(macOS 15, iOS 18, *)
    private func hdrDifference(_ a: CIImage, _ b: CIImage) throws -> Double {
        let width = Int(min(a.extent.width, b.extent.width))
        let height = Int(min(a.extent.height, b.extent.height))
        let first = try hdr(a, width: width, height: height)
        let second = try hdr(b, width: width, height: height)
        var total = 0.0

        for index in first.indices where index % 4 != 3 {
            total += Double(abs(first[index] - second[index]))
        }

        return total / Double(width * height * 3)
    }

    /// `output`'s image and metadata with `source`'s maps carried as they were, uncropped.
    @available(macOS 15, iOS 18, *)
    private func withUncroppedMaps(_ output: URL, from source: URL, formats: [AdjustmentFileFixtures.GainMapFormat]) throws -> URL {
        let url = directory.appendingPathComponent("control-\(UUID().uuidString)").appendingPathExtension(output.pathExtension)
        let written = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        let original = try #require(CGImageSourceCreateWithURL(source as CFURL, nil))
        let type = try #require(CGImageSourceGetType(written))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil))
        let orientation = try properties(output)[kCGImagePropertyOrientation as String] as? Int ?? 1

        CGImageDestinationAddImageAndMetadata(
            destination, try #require(CGImageSourceCreateImageAtIndex(written, 0, nil)), CGImageSourceCopyMetadataAtIndex(written, 0, nil),
            [kCGImagePropertyOrientation: orientation] as CFDictionary
        )

        for format in formats {
            let info = try #require(CGImageSourceCopyAuxiliaryDataInfoAtIndex(original, 0, format.auxiliaryType))
            CGImageDestinationAddAuxiliaryDataInfo(destination, format.auxiliaryType, info)
        }

        try #require(CGImageDestinationFinalize(destination))
        return url
    }

    /// A map carried uncropped lights the wrong areas, so the HDR decode is further from the source's.
    @available(macOS 15, iOS 18, *)
    private func expectCroppedMapsFollow(
        type: UTType,
        formats: [AdjustmentFileFixtures.GainMapFormat],
        orientation: Int,
        crop: CropEdit? = nil,
        comparesHDR: Bool = true
    ) async throws {
        let crop = crop ?? self.crop
        let directory = directory
        let source = try await AdjustmentFileFixtures.checkerMapped(type, formats: formats, orientation: orientation, in: directory)
        let output = destination(source)

        try await renderer.renderFile(ImageAdjustmentDescription(), crop: crop, source: source, destination: output)

        let stored = crop.unoriented(fileOrientation: orientation)

        for format in formats {
            let sourceMap = try mapSize(format.info(source))
            let expected = stored.keptPixelSize(imageWidth: sourceMap.width, imageHeight: sourceMap.height)
            let written = try mapSize(format.info(output))

            #expect(written == expected, "\(type.identifier) \(format) tag \(orientation)")
        }

        guard comparesHDR else { return }

        let reference = crop.apply(to: try hdrDecode(source))
        // An AVIF control is an AV1 encode, which blocks its thread on Dispatch work.
        let control = try await BlockingCallLimiter.shared.run { try withUncroppedMaps(output, from: source, formats: formats) }
        let cropped = try hdrDifference(try hdrDecode(output), reference)
        let uncropped = try hdrDifference(try hdrDecode(control), reference)

        #expect(cropped < uncropped, "\(type.identifier) \(formats) tag \(orientation): cropped \(cropped), uncropped \(uncropped)")
    }

    @Test(arguments: [UTType.jpeg, .heic], AdjustmentFileFixtures.GainMapFormat.allCases)
    func aCroppedSaveCropsItsGainMap(type: UTType, format: AdjustmentFileFixtures.GainMapFormat) async throws {
        guard #available(macOS 15, iOS 18, *) else { return }
        try await expectCroppedMapsFollow(type: type, formats: [format], orientation: 1)
    }

    @Test(arguments: [UTType.jpeg, .heic], AdjustmentFileFixtures.GainMapFormat.allCases)
    func aCroppedSaveOfATurnedFileCropsItsGainMapInStoredPixels(type: UTType, format: AdjustmentFileFixtures.GainMapFormat) async throws {
        guard #available(macOS 15, iOS 18, *) else { return }
        try await expectCroppedMapsFollow(type: type, formats: [format], orientation: 6)
    }

    @Test(arguments: AdjustmentFileFixtures.GainMapFormat.allCases)
    func aCroppedAVIFCropsItsGainMap(format: AdjustmentFileFixtures.GainMapFormat) async throws {
        guard #available(macOS 15, iOS 18, *) else { return }
        try await expectCroppedMapsFollow(type: AdjustmentFileFixtures.avif, formats: [format], orientation: 1)
    }

    @Test func aCroppedTwoMapHEICCarriesBoth() async throws {
        guard #available(macOS 15, iOS 18, *) else { return }
        try await expectCroppedMapsFollow(type: .heic, formats: [.apple, .iso], orientation: 6)
    }

    // MARK: - Perspective

    @Test(arguments: [UTType.jpeg, .heic, AdjustmentFileFixtures.avif], AdjustmentFileFixtures.GainMapFormat.allCases)
    func aCorrectedSaveCorrectsItsGainMap(type: UTType, format: AdjustmentFileFixtures.GainMapFormat) async throws {
        guard #available(macOS 15, iOS 18, *) else { return }
        try await expectCroppedMapsFollow(type: type, formats: [format], orientation: 1, crop: corrected)
    }

    @Test(arguments: [UTType.jpeg, .heic], AdjustmentFileFixtures.GainMapFormat.allCases)
    func aCorrectedSaveOfATurnedFileCorrectsItsGainMapInStoredPixels(type: UTType, format: AdjustmentFileFixtures.GainMapFormat) async throws {
        guard #available(macOS 15, iOS 18, *) else { return }
        try await expectCroppedMapsFollow(type: type, formats: [format], orientation: 6, crop: corrected)
    }

    @Test func aCorrectedTwoMapHEICCarriesBoth() async throws {
        guard #available(macOS 15, iOS 18, *) else { return }
        try await expectCroppedMapsFollow(type: .heic, formats: [.apple, .iso], orientation: 6, crop: corrected)
    }

    // MARK: - Auxiliary images

    @Test func aCropCarriesOnlyTheGainMaps() {
        let strings = { (types: [CFString]) in Set(types.map { $0 as String }) }
        let cropped = strings(ImageFormatConverter.carriedAuxiliaryTypes(cropped: true))
        let uncropped = strings(ImageFormatConverter.carriedAuxiliaryTypes(cropped: false))

        #expect(cropped == strings(ImageFormatConverter.gainMapAuxiliaryTypes))
        #expect(uncropped == strings(ImageFileWriting.auxiliaryDataTypes))
        #expect(!cropped.contains(kCGImageAuxiliaryDataTypeDisparity as String))
        #expect(uncropped.contains(kCGImageAuxiliaryDataTypeDisparity as String))
    }

    // MARK: - EXIF

    @Test(arguments: [UTType.jpeg, .heic])
    func theEXIFSizeIsTheWrittenSize(type: UTType) async throws {
        let source = try await AdjustmentFileFixtures.tagged(type, orientation: 6, in: directory)
        let output = destination(source)

        try await renderer.renderFile(ImageAdjustmentDescription(), crop: crop, source: source, destination: output)

        let written = try properties(output)
        let exif = try #require(written[kCGImagePropertyExifDictionary as String] as? [String: Any])

        #expect(exif[kCGImagePropertyExifPixelXDimension as String] as? Int == written[kCGImagePropertyPixelWidth as String] as? Int)
        #expect(exif[kCGImagePropertyExifPixelYDimension as String] as? Int == written[kCGImagePropertyPixelHeight as String] as? Int)
    }
}
