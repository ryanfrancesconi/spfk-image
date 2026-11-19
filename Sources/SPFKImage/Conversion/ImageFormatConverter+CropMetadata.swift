// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import ImageIO
import SPFKBase

extension ImageFormatConverter {
    /// Sets EXIF `PixelXDimension` and `PixelYDimension`, which ImageIO leaves stale in a HEIC whose
    /// size changed.
    static func setPixelDimensions(_ metadata: CGMutableImageMetadata, width: Int, height: Int) {
        CGImageMetadataSetValueMatchingImageProperty(
            metadata, kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelXDimension, width as CFNumber
        )
        CGImageMetadataSetValueMatchingImageProperty(
            metadata, kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelYDimension, height as CFNumber
        )
    }

    private static let regions = "mwg-rs:Regions"
    private static let regionList = "mwg-rs:Regions.mwg-rs:RegionList"

    /// Moves each normalized `mwg-rs` region of a `storedWidth × storedHeight` file through a render that
    /// turns it by `before`, crops it by `crop` and turns it by `after`, and states the written size.
    /// A region whose center leaves the kept area is removed; one in another unit is left alone.
    static func remapRegions(
        _ metadata: CGMutableImageMetadata,
        storedWidth: Int,
        storedHeight: Int,
        before: OrientationEdit,
        crop: CropEdit,
        after: OrientationEdit,
        writtenWidth: Int,
        writtenHeight: Int
    ) {
        guard let list = CGImageMetadataCopyTagWithPath(metadata, nil, regionList as CFString),
              let items = CGImageMetadataTagCopyValue(list) as? [CGImageMetadataTag]
        else { return }

        let mapping = RegionMapping(
            storedWidth: storedWidth, storedHeight: storedHeight, before: before, crop: crop, after: after
        )
        var kept: [Int] = []

        for index in items.indices {
            let area = "\(regionList)[\(index)].mwg-rs:Area.stArea:"

            func value(_ name: String) -> Double? {
                (CGImageMetadataCopyStringValueWithPath(metadata, nil, (area + name) as CFString) as String?).flatMap(Double.init)
            }

            guard (CGImageMetadataCopyStringValueWithPath(metadata, nil, (area + "unit") as CFString) as String?) == "normalized",
                  let x = value("x"), let y = value("y"), let w = value("w"), let h = value("h")
            else {
                kept.append(index)
                continue
            }

            guard let region = mapping.region(x: x, y: y, w: w, h: h) else { continue }

            for (name, number) in [("x", region.x), ("y", region.y), ("w", region.w), ("h", region.h)] {
                CGImageMetadataSetValueWithPath(metadata, nil, (area + name) as CFString, String(number) as CFString)
            }

            kept.append(index)
        }

        if kept.isEmpty {
            CGImageMetadataRemoveTagWithPath(metadata, nil, regions as CFString)
            return
        }

        if kept.count < items.count,
           let updated = CGImageMetadataCopyTagWithPath(metadata, nil, regionList as CFString),
           let updatedItems = CGImageMetadataTagCopyValue(updated) as? [CGImageMetadataTag],
           let namespace = CGImageMetadataTagCopyNamespace(updated),
           let prefix = CGImageMetadataTagCopyPrefix(updated),
           let name = CGImageMetadataTagCopyName(updated),
           let filtered = CGImageMetadataTagCreate(
               namespace, prefix, name, CGImageMetadataTagGetType(updated), kept.map { updatedItems[$0] } as CFArray
           )
        {
            CGImageMetadataSetTagWithPath(metadata, nil, regionList as CFString, filtered)
        }

        let dimensions = "\(regions).mwg-rs:AppliedToDimensions.stDim:"

        if CGImageMetadataCopyTagWithPath(metadata, nil, (dimensions + "w") as CFString) != nil {
            CGImageMetadataSetValueWithPath(metadata, nil, (dimensions + "w") as CFString, String(writtenWidth) as CFString)
            CGImageMetadataSetValueWithPath(metadata, nil, (dimensions + "h") as CFString, String(writtenHeight) as CFString)
        }
    }
}

/// A normalized region of the stored pixels, followed through a turn, a crop and a turn.
struct RegionMapping {
    let before: OrientationEdit
    let after: OrientationEdit
    let displayedWidth: Double
    let displayedHeight: Double
    let center: SIMD2<Double>
    let keptWidth: Double
    let keptHeight: Double
    let radians: Double

    init(storedWidth: Int, storedHeight: Int, before: OrientationEdit, crop: CropEdit, after: OrientationEdit) {
        let width = before.swapsDimensions ? storedHeight : storedWidth
        let height = before.swapsDimensions ? storedWidth : storedHeight
        let contained = crop.contained(imageWidth: width, imageHeight: height)
        let kept = crop.keptPixelSize(imageWidth: width, imageHeight: height)

        self.before = before
        self.after = after
        displayedWidth = Double(width)
        displayedHeight = Double(height)
        center = contained.pixelCenter(imageWidth: width, imageHeight: height)
        keptWidth = Double(kept.width)
        keptHeight = Double(kept.height)
        radians = contained.straighten * .pi / 180
    }

    /// The region's center and size as fractions of the written picture, or nil when its center is
    /// outside it.
    func region(x: Double, y: Double, w: Double, h: Double) -> (x: Double, y: Double, w: Double, h: Double)? {
        let shown = before.shownUnitPoint(forDisplayed: SIMD2(x, y))
        let offset = SIMD2(shown.x * displayedWidth, shown.y * displayedHeight) - center

        // Clockwise as displayed, y down.
        let c = cos(radians)
        let s = sin(radians)
        let turned = SIMD2(c * offset.x - s * offset.y, s * offset.x + c * offset.y)
        let inCrop = SIMD2(turned.x / keptWidth + 0.5, turned.y / keptHeight + 0.5)

        guard (0 ... 1).contains(inCrop.x), (0 ... 1).contains(inCrop.y) else { return nil }

        let point = after.shownUnitPoint(forDisplayed: inCrop)
        let storedSize = before.swapsDimensions ? SIMD2(h, w) : SIMD2(w, h)
        var size = SIMD2(
            storedSize.x * displayedWidth / keptWidth,
            storedSize.y * displayedHeight / keptHeight
        )

        if after.swapsDimensions {
            size = SIMD2(size.y, size.x)
        }

        return (point.x, point.y, size.x, size.y)
    }
}
