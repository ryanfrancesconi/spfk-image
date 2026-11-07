// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

/// Each edit checked against pixels: a 2×3 bitmap whose six values are distinct, compared after
/// ImageIO displays a tagged file and after ``ImageOrientationEdit/apply(to:)``.
struct ImageOrientationEditTests {
    typealias Grid = [[Int]]

    /// Two wide, three tall, top row first.
    static let values: Grid = [[20, 60], [100, 140], [180, 220]]

    private let context = CIContext()

    // MARK: - Pixel helpers

    static func image(_ grid: Grid) throws -> CGImage {
        let height = grid.count, width = grid[0].count
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        let pixels = try #require(context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4))

        for row in 0 ..< height {
            for column in 0 ..< width {
                let offset = (row * width + column) * 4
                pixels[offset] = UInt8(grid[row][column])
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
            }
        }

        return try #require(context.makeImage())
    }

    /// The red channel, top row first, each value snapped to the nearest of ``values``.
    static func grid(_ image: CGImage) throws -> Grid {
        let width = image.width, height = image.height
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try #require(context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4))
        let known = values.flatMap { $0 }

        return (0 ..< height).map { row in
            (0 ..< width).map { column in
                let red = Int(pixels[(row * width + column) * 4])
                return known.min { abs($0 - red) < abs($1 - red) } ?? red
            }
        }
    }

    /// What ImageIO displays for a PNG of `grid` tagged `orientation`.
    static func displayed(_ grid: Grid, tag orientation: Int) throws -> Grid {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try image(grid), [kCGImagePropertyOrientation: orientation] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))

        let source = try #require(CGImageSourceCreateWithData(data, nil))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3,
        ]

        return try Self.grid(try #require(CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)))
    }

    private func applied(_ edit: ImageOrientationEdit, to grid: Grid) throws -> Grid {
        let output = edit.apply(to: CIImage(cgImage: try Self.image(grid)))
        #expect(output.extent.origin == .zero)
        return try Self.grid(try #require(context.createCGImage(output, from: output.extent)))
    }

    // MARK: - Definition

    @Test(arguments: ImageOrientationEdit.allCases)
    func applyMatchesImageIOsDisplayOfTheTag(edit: ImageOrientationEdit) throws {
        #expect(try applied(edit, to: Self.values) == Self.displayed(Self.values, tag: edit.rawValue))
    }

    /// An edit performed on a tagged file's display matches the file retagged with the composed value.
    @Test(arguments: ImageOrientationEdit.allCases, ImageOrientationEdit.allCases)
    func composedTagDisplaysTheEditedImage(edit: ImageOrientationEdit, file: ImageOrientationEdit) throws {
        let shown = try Self.displayed(Self.values, tag: file.rawValue)

        #expect(try applied(edit, to: shown) == Self.displayed(Self.values, tag: edit.applied(toFileOrientation: file.rawValue)))
    }

    @Test(arguments: ImageOrientationEdit.allCases, ImageOrientationEdit.Command.allCases)
    func aCommandActsOnTheDisplayedImage(start: ImageOrientationEdit, command: ImageOrientationEdit.Command) throws {
        let shown = try applied(start, to: Self.values)

        #expect(try applied(start.applying(command), to: Self.values) == applied(command.edit, to: shown))
    }

    @Test func rotateRightIsClockwise() throws {
        #expect(try applied(ImageOrientationEdit.up.rotatedRight, to: Self.values) == [[180, 100, 20], [220, 140, 60]])
    }

    @Test func rotateLeftIsCounterclockwise() throws {
        #expect(try applied(ImageOrientationEdit.up.rotatedLeft, to: Self.values) == [[60, 140, 220], [20, 100, 180]])
    }

    @Test func flipHorizontalMirrorsLeftToRight() throws {
        #expect(try applied(ImageOrientationEdit.up.flippedHorizontally, to: Self.values) == [[60, 20], [140, 100], [220, 180]])
    }

    @Test func flipVerticalMirrorsTopToBottom() throws {
        #expect(try applied(ImageOrientationEdit.up.flippedVertically, to: Self.values) == [[180, 220], [100, 140], [20, 60]])
    }

    @Test(arguments: ImageOrientationEdit.allCases)
    func thePreviewRenderIsOriented(edit: ImageOrientationEdit) throws {
        let rendered = try #require(ImageAdjustmentRenderer().render(ImageAdjustmentDescription(), orientation: edit, source: Self.image(Self.values)))

        #expect(try Self.grid(rendered) == applied(edit, to: Self.values))
    }

    // MARK: - Group identities

    @Test(arguments: ImageOrientationEdit.allCases)
    func fourRotationsReturnToTheStart(start: ImageOrientationEdit) {
        #expect(start.rotatedRight.rotatedRight.rotatedRight.rotatedRight == start)
        #expect(start.rotatedLeft.rotatedLeft.rotatedLeft.rotatedLeft == start)
        #expect(start.rotatedLeft.rotatedRight == start)
    }

    @Test(arguments: ImageOrientationEdit.allCases)
    func twoFlipsReturnToTheStart(start: ImageOrientationEdit) {
        #expect(start.flippedHorizontally.flippedHorizontally == start)
        #expect(start.flippedVertically.flippedVertically == start)
    }

    @Test func rotateRightThenFlipHorizontalEqualsFlipVerticalThenRotateRight() throws {
        let first = ImageOrientationEdit.up.rotatedRight.flippedHorizontally
        let second = ImageOrientationEdit.up.flippedVertically.rotatedRight

        #expect(try applied(first, to: Self.values) == applied(second, to: Self.values))
    }

    @Test(arguments: ImageOrientationEdit.allCases)
    func swapsDimensionsMatchesTheDisplayedShape(edit: ImageOrientationEdit) throws {
        let shown = try applied(edit, to: Self.values)
        #expect(edit.swapsDimensions == (shown.count == 2))
    }

    @Test(arguments: [0, 9, -1])
    func anOutOfRangeFileTagReadsAsUp(tag: Int) {
        #expect(ImageOrientationEdit.right.applied(toFileOrientation: tag) == ImageOrientationEdit.right.rawValue)
    }
}
