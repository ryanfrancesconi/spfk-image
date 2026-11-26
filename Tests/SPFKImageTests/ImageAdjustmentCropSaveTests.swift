// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import ImageIO
import SPFKBase
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

/// The crop's definition: the preview, Save and Convert Files show the same picture for every file tag,
/// pending orientation and crop, perspective included.
@Suite(.tags(.file))
final class ImageAdjustmentCropSaveTests {
    private let directory: URL
    private let renderer = ImageAdjustmentRenderer()

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spfk-image-crop-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    static let crops: [CropEdit] = [
        CropEdit(centerX: 0.1, centerY: -0.15, width: 0.5, height: 0.4),
        CropEdit(centerX: 0.1, centerY: -0.15, width: 0.5, height: 0.4, straighten: 7),
        CropEdit(width: 0.333, height: 0.333, straighten: -20),
        CropEdit(vertical: 12),
        CropEdit(straighten: 7, horizontal: -10),
        CropEdit(centerX: 0.1, centerY: -0.15, width: 0.4, height: 0.5, vertical: -8, horizontal: 6),
    ]

    /// Phase 1's threshold, at the best offset of up to a pixel: a crop edge on a half pixel lands one pixel
    /// apart under a mirror or a turn, 1.62 levels unshifted on this fixture and under 0.001 shifted.
    private static let tolerance = 1.5

    private func uprightDecode(_ url: URL) throws -> CGImage {
        let image = try #require(CIImage(contentsOf: url, options: [.applyOrientationProperty: true]))
        return try #require(renderer.context.createCGImage(image, from: image.extent))
    }

    /// RGBA8 sRGB bytes, top row first.
    private func bytes(_ image: CGImage) throws -> [UInt8] {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)

        try data.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }

        return data
    }

    /// Mean absolute RGB difference in levels of 255 with `b` shifted by `dx`, `dy`, over the pixels both
    /// cover less a 1-pixel border.
    private func meanDifference(_ a: [UInt8], _ b: [UInt8], width: Int, height: Int, dx: Int = 0, dy: Int = 0) -> Double {
        var total = 0
        var count = 0

        for y in 1 ..< height - 1 {
            for x in 1 ..< width - 1 {
                let first = (y * width + x) * 4
                let second = ((y + dy) * width + x + dx) * 4
                for channel in 0 ..< 3 {
                    total += abs(Int(a[first + channel]) - Int(b[second + channel]))
                    count += 1
                }
            }
        }

        return Double(total) / Double(count)
    }

    /// The file's orientation tag, 1 when it carries none.
    private func orientationTag(of url: URL) throws -> Int {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])

        return properties[kCGImagePropertyOrientation as String] as? Int ?? 1
    }

    /// The lowest ``meanDifference(_:_:width:height:dx:dy:)`` over every shift of up to a pixel.
    private func bestMeanDifference(_ a: [UInt8], _ b: [UInt8], width: Int, height: Int) -> Double {
        var best = Double.infinity

        for dy in -1 ... 1 {
            for dx in -1 ... 1 {
                best = min(best, meanDifference(a, b, width: width, height: height, dx: dx, dy: dy))
            }
        }

        return best
    }

    @Test(arguments: OrientationEdit.allCases, crops)
    func previewSaveAndConvertShowTheSamePicture(tag: OrientationEdit, crop: CropEdit) async throws {
        let source = try AdjustmentFileFixtures.asymmetric(.tiff, orientation: tag.rawValue, in: directory)
        try #require(try orientationTag(of: source) == tag.rawValue)

        let upright = try uprightDecode(source)

        for pending in OrientationEdit.allCases {
            let preview = try #require(renderer.render(ImageAdjustmentDescription(), orientation: pending, cropEdit: crop, source: upright))

            let saved = directory.appendingPathComponent("saved-\(UUID().uuidString).tiff")
            try await renderer.renderFile(ImageAdjustmentDescription(), orientation: pending, crop: crop, source: source, destination: saved)
            let save = try uprightDecode(saved)

            let converted = directory.appendingPathComponent("converted-\(UUID().uuidString).tiff")
            _ = try await ImageFormatConverter(source: ImageConversionSource(
                input: source, output: converted, options: ImageConversionOptions(format: UTType.tiff.identifier),
                orientation: pending, crop: crop
            )).convert()
            let convert = try uprightDecode(converted)

            for (name, image) in [("save", save), ("convert", convert)] {
                let label = "\(name) tag \(tag) pending \(pending) crop \(crop.width)x\(crop.height) at \(crop.straighten) V\(crop.vertical) H\(crop.horizontal)"
                try #require(image.width == preview.width && image.height == preview.height, "\(label): \(image.width)x\(image.height) against \(preview.width)x\(preview.height)")

                let first = try bytes(image)
                let second = try bytes(preview)
                let unshifted = meanDifference(first, second, width: image.width, height: image.height)
                let best = bestMeanDifference(first, second, width: image.width, height: image.height)
                #expect(best < Self.tolerance, "\(label): \(best), unshifted \(unshifted)")
            }
        }
    }
}
