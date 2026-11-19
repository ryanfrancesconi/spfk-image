// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import ImageIO
import SPFKBase

extension ImageFormatConverter {
    /// Renders gain maps without keeping their intermediates, which are per file.
    static let auxiliaryContext = CIContext(options: [.cacheIntermediates: false])

    /// The auxiliary images a render carries: every one, or for a crop only the gain maps, since depth
    /// and mattes are dropped rather than cropped.
    static func carriedAuxiliaryTypes(cropped: Bool) -> [CFString] {
        cropped ? gainMapAuxiliaryTypes : ImageAdjustmentRenderer.auxiliaryDataTypes
    }

    /// `info` with its map turned by `before`, cropped by `crop` and turned by `after`, at the map's own
    /// resolution, or nil when it needs changing and is not one 8-bit component.
    static func transformedAuxiliaryData(
        _ info: [String: Any],
        before: OrientationEdit,
        crop: CropEdit,
        after: OrientationEdit
    ) -> [String: Any]? {
        guard !crop.isIdentity else {
            return orientedAuxiliaryData(info, orientation: after.applied(toFileOrientation: before.rawValue))
        }

        guard let data = info[kCGImageAuxiliaryDataInfoData as String] as? Data,
              var description = info[kCGImageAuxiliaryDataInfoDataDescription as String] as? [String: Any],
              description["PixelFormat"] as? Int == oneComponent8PixelFormat,
              let width = description["Width"] as? Int,
              let height = description["Height"] as? Int,
              let bytesPerRow = description["BytesPerRow"] as? Int,
              width > 0, height > 0, bytesPerRow >= width,
              data.count >= bytesPerRow * height
        else { return nil }

        let map = CIImage(
            bitmapData: data, bytesPerRow: bytesPerRow, size: CGSize(width: width, height: height), format: .L8, colorSpace: nil
        )
        let transformed = after.apply(to: crop.apply(to: before.apply(to: map)))
        let extent = transformed.extent.integral
        let outputWidth = Int(extent.width)
        let outputHeight = Int(extent.height)
        guard outputWidth > 0, outputHeight > 0 else { return nil }

        var output = Data(count: outputWidth * outputHeight)

        output.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            auxiliaryContext.render(
                transformed, toBitmap: base, rowBytes: outputWidth, bounds: extent, format: .L8, colorSpace: nil
            )
        }

        description["Width"] = outputWidth
        description["Height"] = outputHeight
        description["BytesPerRow"] = outputWidth

        var result = info
        result[kCGImageAuxiliaryDataInfoData as String] = output
        result[kCGImageAuxiliaryDataInfoDataDescription as String] = description
        return result
    }
}
