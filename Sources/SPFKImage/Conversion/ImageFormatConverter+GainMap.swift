// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import ImageIO

extension ImageFormatConverter {
    /// 'L008', one 8-bit component: the layout of every gain map measured, Apple's and ISO's.
    static let oneComponent8PixelFormat = 1_278_226_488

    static var gainMapAuxiliaryTypes: [CFString] {
        var types: [CFString] = [kCGImageAuxiliaryDataTypeHDRGainMap]

        if #available(macOS 15, iOS 18, *) {
            types.append(kCGImageAuxiliaryDataTypeISOGainMap)
        }

        return types
    }

    /// Adds each gain map, laid out as `orientation` displays it. A map smaller than the image is left to the
    /// reader to scale, as it is in the source.
    static func addGainMaps(from imageSource: CGImageSource, index: Int, orientation: Int, to destination: CGImageDestination) {
        for type in gainMapAuxiliaryTypes {
            guard let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(imageSource, index, type) as? [String: Any],
                  let oriented = orientedAuxiliaryData(info, orientation: orientation)
            else { continue }

            CGImageDestinationAddAuxiliaryDataInfo(destination, type, oriented as CFDictionary)
        }
    }

    /// `info` with its map reordered into `orientation`'s displayed layout, or `nil` when it needs reordering and
    /// is not one 8-bit component.
    static func orientedAuxiliaryData(_ info: [String: Any], orientation: Int) -> [String: Any]? {
        guard orientation != 1 else { return info }

        guard (2 ... 8).contains(orientation),
              let data = info[kCGImageAuxiliaryDataInfoData as String] as? Data,
              var description = info[kCGImageAuxiliaryDataInfoDataDescription as String] as? [String: Any],
              description["PixelFormat"] as? Int == oneComponent8PixelFormat,
              let width = description["Width"] as? Int,
              let height = description["Height"] as? Int,
              let bytesPerRow = description["BytesPerRow"] as? Int,
              width > 0, height > 0, bytesPerRow >= width,
              data.count >= bytesPerRow * (height - 1) + width
        else { return nil }

        let reordered = reorder(data, width: width, height: height, bytesPerRow: bytesPerRow, orientation: orientation)

        description["Width"] = reordered.width
        description["Height"] = reordered.height
        description["BytesPerRow"] = reordered.width

        var oriented = info
        oriented[kCGImageAuxiliaryDataInfoData as String] = reordered.data
        oriented[kCGImageAuxiliaryDataInfoDataDescription as String] = description
        return oriented
    }

    /// A one-component 8-bit map laid out as `orientation` displays it, with no row padding.
    static func reorder(
        _ data: Data,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        orientation: Int
    ) -> (data: Data, width: Int, height: Int) {
        let rotates = orientation >= 5
        let outputWidth = rotates ? height : width
        let outputHeight = rotates ? width : height
        var output = [UInt8](repeating: 0, count: outputWidth * outputHeight)

        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for y in 0 ..< outputHeight {
                for x in 0 ..< outputWidth {
                    let (sourceX, sourceY): (Int, Int) = switch orientation {
                    case 2: (width - 1 - x, y)
                    case 3: (width - 1 - x, height - 1 - y)
                    case 4: (x, height - 1 - y)
                    case 5: (y, x)
                    case 6: (y, height - 1 - x)
                    case 7: (width - 1 - y, height - 1 - x)
                    case 8: (width - 1 - y, x)
                    default: (x, y)
                    }

                    output[y * outputWidth + x] = bytes[sourceY * bytesPerRow + sourceX]
                }
            }
        }

        return (Data(output), outputWidth, outputHeight)
    }
}
