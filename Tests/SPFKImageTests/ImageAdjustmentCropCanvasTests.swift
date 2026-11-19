// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import SPFKBase
import Testing

@testable import SPFKImage

/// Crop mode shows the oriented picture turned by ``CropCanvas/shownAngle`` under an axis-aligned
/// frame; the committed render crops and straightens first, then orients. The frame's contents must
/// be the committed picture, through every orientation, mirrors included.
@Suite
final class ImageAdjustmentCropCanvasTests {
    private let renderer = ImageAdjustmentRenderer()

    /// Mean absolute difference in levels of 255. Resampling and the committed render's whole-pixel
    /// origin account for it; a wrong sign or center is an order of magnitude more.
    private static let tolerance = 1.5

    private static let crop = CropEdit(centerX: 0.12, centerY: -0.08, width: 0.5, height: 0.4)

    static let cases: [(OrientationEdit, Double)] = OrientationEdit.allCases.flatMap { orientation in
        [0.0, 7, -20].map { (orientation, $0) }
    }

    // MARK: - Fixture

    /// 400 × 240 in four colored quadrants, with an 8-pixel black mark off center in the top-left one.
    private func quadrants() throws -> CGImage {
        let width = 400
        let height = 240
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))

        // Core Graphics is y up: the top half is at `height / 2`.
        let fills: [((CGFloat, CGFloat, CGFloat), CGRect)] = [
            ((1, 0, 0), CGRect(x: 0, y: 120, width: 200, height: 120)),
            ((0, 1, 0), CGRect(x: 200, y: 120, width: 200, height: 120)),
            ((0, 0, 1), CGRect(x: 0, y: 0, width: 200, height: 120)),
            ((1, 1, 1), CGRect(x: 200, y: 0, width: 200, height: 120)),
            ((0, 0, 0), CGRect(x: 150, y: 240 - 100 - 8, width: 8, height: 8)),
        ]

        for ((r, g, b), rect) in fills {
            context.setFillColor(red: r, green: g, blue: b, alpha: 1)
            context.fill(rect)
        }

        return try #require(context.makeImage())
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

    private func meanDifference(_ a: CGImage, _ b: CGImage) throws -> Double {
        let first = try bytes(a)
        let second = try bytes(b)
        var total = 0
        var count = 0

        for index in stride(from: 0, to: first.count, by: 4) {
            for channel in 0 ..< 3 {
                total += abs(Int(first[index + channel]) - Int(second[index + channel]))
                count += 1
            }
        }

        return Double(total) / Double(count)
    }

    // MARK: - Paths

    /// The oriented picture turned clockwise by `angle` about its center into the canvas, and the frame
    /// cut from it at `size`.
    private func cropModeFrame(source: CGImage, canvas: CropCanvas, angle: Double, size: CGSize) throws -> CGImage {
        let oriented = canvas.orientation.apply(to: CIImage(cgImage: source)).clampedToExtent()
        let shown = canvas.shownSize
        let bounding = canvas.boundingSize

        // Clockwise on screen is negative in Core Image's y-up space.
        let turn = CGAffineTransform(translationX: -shown.x / 2, y: -shown.y / 2)
            .concatenating(CGAffineTransform(rotationAngle: -angle * .pi / 180))
            .concatenating(CGAffineTransform(translationX: bounding.x / 2, y: bounding.y / 2))
        let turned = oriented.transformed(by: turn)

        let center = canvas.frameCenter
        let origin = CGPoint(x: center.x - size.width / 2, y: bounding.y - center.y - size.height / 2)
        let frame = turned.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))

        return try #require(renderer.context.createCGImage(frame, from: CGRect(origin: .zero, size: size)))
    }

    // MARK: - Tests

    @Test(arguments: cases)
    func theFrameShowsWhatTheCommittedRenderKeeps(orientation: OrientationEdit, straighten: Double) throws {
        let source = try quadrants()
        var crop = Self.crop
        crop.straighten = straighten
        crop = crop.contained(imageWidth: source.width, imageHeight: source.height)

        let committed = try #require(renderer.render(ImageAdjustmentDescription(), orientation: orientation, cropEdit: crop, source: source))
        let canvas = CropCanvas(crop: crop, imageWidth: source.width, imageHeight: source.height, orientation: orientation)
        let size = CGSize(width: committed.width, height: committed.height)

        #expect(abs(canvas.frameSize.x - size.width) <= 1 && abs(canvas.frameSize.y - size.height) <= 1)

        let shown = try cropModeFrame(source: source, canvas: canvas, angle: canvas.shownAngle, size: size)
        let match = try meanDifference(committed, shown)
        #expect(match < Self.tolerance, "\(orientation) \(straighten)°: mean difference \(match)")

        guard straighten != 0 else { return }

        let opposite = try meanDifference(committed, cropModeFrame(source: source, canvas: canvas, angle: -canvas.shownAngle, size: size))
        #expect(opposite > max(match * 4, Self.tolerance), "\(orientation) \(straighten)°: opposite turn \(opposite) against \(match)")
    }
}
