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
///
/// A perspective correction moves the region's center through the homography and scales each side by
/// the map's local scale at that center, which is close enough for a region as small as a face.
struct RegionMapping {
    let before: OrientationEdit
    let after: OrientationEdit
    let displayedWidth: Double
    let displayedHeight: Double
    let perspective: Homography?
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
        perspective = crop.hasPerspective ? crop.perspective(imageWidth: width, imageHeight: height) : nil
        center = contained.pixelCenter(imageWidth: width, imageHeight: height)
        keptWidth = Double(kept.width)
        keptHeight = Double(kept.height)
        radians = contained.straighten * .pi / 180
    }

    /// The region's center and size as fractions of the written picture, or nil when its center is
    /// outside it.
    func region(x: Double, y: Double, w: Double, h: Double) -> (x: Double, y: Double, w: Double, h: Double)? {
        let shown = before.shownUnitPoint(forDisplayed: SIMD2(x, y))
        var position = SIMD2(shown.x * displayedWidth, shown.y * displayedHeight)
        var scale = SIMD2<Double>(1, 1)

        if let perspective {
            guard perspective.weight(position) > 0 else { return nil }
            scale = Self.sideScale(of: perspective, at: position)
            position = perspective.apply(position)
        }

        let offset = position - center

        // Clockwise as displayed, y down.
        let c = cos(radians)
        let s = sin(radians)
        let turned = SIMD2(c * offset.x - s * offset.y, s * offset.x + c * offset.y)
        let inCrop = SIMD2(turned.x / keptWidth + 0.5, turned.y / keptHeight + 0.5)

        guard (0 ... 1).contains(inCrop.x), (0 ... 1).contains(inCrop.y) else { return nil }

        let point = after.shownUnitPoint(forDisplayed: inCrop)
        let storedSize = before.swapsDimensions ? SIMD2(h, w) : SIMD2(w, h)
        var size = SIMD2(
            storedSize.x * scale.x * displayedWidth / keptWidth,
            storedSize.y * scale.y * displayedHeight / keptHeight
        )

        if after.swapsDimensions {
            size = SIMD2(size.y, size.x)
        }

        return (point.x, point.y, size.x, size.y)
    }

    /// How much `map` stretches a horizontal and a vertical segment at `point`: the lengths of its
    /// Jacobian's columns there.
    static func sideScale(of map: Homography, at point: SIMD2<Double>) -> SIMD2<Double> {
        let p = SIMD3(point.x, point.y, 1)
        let u = (map.row0 * p).sum()
        let v = (map.row1 * p).sum()
        let w = (map.row2 * p).sum()

        // d(u/w) = (du·w - u·dw) / w², column by column.
        let alongX = SIMD2(map.row0.x * w - u * map.row2.x, map.row1.x * w - v * map.row2.x) / (w * w)
        let alongY = SIMD2(map.row0.y * w - u * map.row2.y, map.row1.y * w - v * map.row2.y) / (w * w)
        return SIMD2((alongX * alongX).sum().squareRoot(), (alongY * alongY).sum().squareRoot())
    }
}
