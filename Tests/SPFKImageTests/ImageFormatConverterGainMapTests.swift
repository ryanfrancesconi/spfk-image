// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import ImageIO
import SPFKBase
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

    // MARK: - Crop

    @Test(arguments: OrientationEdit.allCases)
    func anIdentityCropIsTheByteReorder(orientation: OrientationEdit) throws {
        let map = info(pixelFormat: ImageFormatConverter.oneComponent8PixelFormat)

        for before in OrientationEdit.allCases {
            let transformed = try #require(ImageFormatConverter.transformedAuxiliaryData(map, before: before, crop: CropEdit(), after: orientation))
            let reordered = try #require(
                ImageFormatConverter.orientedAuxiliaryData(map, orientation: orientation.applied(toFileOrientation: before.rawValue))
            )

            #expect(transformed[kCGImageAuxiliaryDataInfoData as String] as? Data == reordered[kCGImageAuxiliaryDataInfoData as String] as? Data)
        }
    }

    @Test func aCroppedMapDescribesItsData() throws {
        let width = 64
        let height = 48
        let map: [String: Any] = [
            kCGImageAuxiliaryDataInfoData as String: Data((0 ..< width * height).map { UInt8($0 % 251) }),
            kCGImageAuxiliaryDataInfoDataDescription as String: [
                "Width": width, "Height": height, "BytesPerRow": width, "PixelFormat": ImageFormatConverter.oneComponent8PixelFormat,
            ] as [String: Any],
        ]
        let crop = CropEdit(centerX: 0.1, width: 0.5, height: 0.4, straighten: 7)

        let transformed = try #require(ImageFormatConverter.transformedAuxiliaryData(map, before: .up, crop: crop, after: .right))
        let description = try #require(transformed[kCGImageAuxiliaryDataInfoDataDescription as String] as? [String: Any])
        let data = try #require(transformed[kCGImageAuxiliaryDataInfoData as String] as? Data)
        let kept = crop.keptPixelSize(imageWidth: width, imageHeight: height)

        #expect(description["Width"] as? Int == kept.height)
        #expect(description["Height"] as? Int == kept.width)
        #expect(description["BytesPerRow"] as? Int == kept.height)
        #expect(data.count == kept.width * kept.height)
    }

    @Test func aCroppedMapInAnotherLayoutIsDropped() {
        let crop = CropEdit(width: 0.5, height: 0.5)
        #expect(ImageFormatConverter.transformedAuxiliaryData(info(pixelFormat: 0x4C30_3130), before: .up, crop: crop, after: .up) == nil)
    }
}
