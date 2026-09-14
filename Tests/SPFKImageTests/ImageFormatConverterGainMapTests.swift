// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import ImageIO
import Testing

@testable import SPFKImage

/// How a gain map is reordered to match an image the render path drew upright.
struct ImageFormatConverterGainMapTests {
    struct Layout: Sendable, CustomTestStringConvertible {
        let orientation: Int
        let width: Int
        let height: Int
        let pixels: [UInt8]

        var testDescription: String { "orientation \(orientation)" }
    }

    /// Stored 3 × 2, rows `1 2 3` and `4 5 6`, each padded by a byte.
    private static let stored = Data([1, 2, 3, 0, 4, 5, 6, 0])

    /// Each layout worked out by hand from what the orientation displays.
    static let layouts: [Layout] = [
        Layout(orientation: 2, width: 3, height: 2, pixels: [3, 2, 1, 6, 5, 4]),
        Layout(orientation: 3, width: 3, height: 2, pixels: [6, 5, 4, 3, 2, 1]),
        Layout(orientation: 4, width: 3, height: 2, pixels: [4, 5, 6, 1, 2, 3]),
        Layout(orientation: 5, width: 2, height: 3, pixels: [1, 4, 2, 5, 3, 6]),
        Layout(orientation: 6, width: 2, height: 3, pixels: [4, 1, 5, 2, 6, 3]),
        Layout(orientation: 7, width: 2, height: 3, pixels: [6, 3, 5, 2, 4, 1]),
        Layout(orientation: 8, width: 2, height: 3, pixels: [3, 6, 2, 5, 1, 4]),
    ]

    @Test(arguments: layouts)
    func aMapIsLaidOutAsItsOrientationDisplays(layout: Layout) {
        let reordered = ImageFormatConverter.reorder(Self.stored, width: 3, height: 2, bytesPerRow: 4, orientation: layout.orientation)

        #expect(reordered.width == layout.width)
        #expect(reordered.height == layout.height)
        #expect([UInt8](reordered.data) == layout.pixels)
    }

    private func info(pixelFormat: Int) -> [String: Any] {
        [
            kCGImageAuxiliaryDataInfoData as String: Self.stored,
            kCGImageAuxiliaryDataInfoDataDescription as String: [
                "Width": 3, "Height": 2, "BytesPerRow": 4, "PixelFormat": pixelFormat,
            ] as [String: Any],
        ]
    }

    @Test func aTurnedMapDescribesItsNewLayout() throws {
        let oriented = try #require(
            ImageFormatConverter.orientedAuxiliaryData(info(pixelFormat: ImageFormatConverter.oneComponent8PixelFormat), orientation: 6)
        )
        let description = try #require(oriented[kCGImageAuxiliaryDataInfoDataDescription as String] as? [String: Any])

        #expect(description["Width"] as? Int == 2)
        #expect(description["Height"] as? Int == 3)
        #expect(description["BytesPerRow"] as? Int == 2)
    }

    /// Dropping the map loses the HDR rendition; keeping it unturned would light the wrong areas.
    @Test func aMapInAnotherLayoutIsDroppedOnlyWhenItNeedsTurning() {
        let other = info(pixelFormat: 0x4C30_3130)

        #expect(ImageFormatConverter.orientedAuxiliaryData(other, orientation: 6) == nil)
        #expect(ImageFormatConverter.orientedAuxiliaryData(other, orientation: 1) != nil)
    }
}
