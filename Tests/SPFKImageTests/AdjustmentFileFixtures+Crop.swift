// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Files for the crop's Save and Convert tests.
extension AdjustmentFileFixtures {
    static let asymmetricWidth = 600
    static let asymmetricHeight = 400

    /// The white mark's center and size in the stored pixels, as fractions.
    static let mark = Region(name: "mark", x: 105.0 / 600, y: 80.0 / 400, w: 50.0 / 600, h: 40.0 / 400)

    /// 600 × 400: four quadrant colors, a white mark off center in the top-left one, and a horizontal ramp
    /// from black to light gray across the middle. No symmetry of the square maps it onto itself, and only
    /// the mark is white.
    static func asymmetricImage() throws -> CGImage {
        let width = asymmetricWidth
        let height = asymmetricHeight

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { throw GenerationError(message: "no RGB context") }

        // Core Graphics is y up.
        let fills: [(CGFloat, CGFloat, CGFloat, CGRect)] = [
            (0.9, 0.1, 0.1, CGRect(x: 0, y: 200, width: 300, height: 200)),
            (0.1, 0.8, 0.2, CGRect(x: 300, y: 200, width: 300, height: 200)),
            (0.1, 0.2, 0.9, CGRect(x: 0, y: 0, width: 300, height: 200)),
            (0.9, 0.8, 0.1, CGRect(x: 300, y: 0, width: 300, height: 200)),
            (1, 1, 1, CGRect(x: 80, y: height - 60 - 40, width: 50, height: 40)),
        ]

        for (red, green, blue, rect) in fills {
            context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
            context.fill(rect)
        }

        for x in 0 ..< width {
            let level = 0.8 * CGFloat(x) / CGFloat(width - 1)
            context.setFillColor(red: level, green: level, blue: level, alpha: 1)
            context.fill(CGRect(x: x, y: 180, width: 1, height: 40))
        }

        guard let image = context.makeImage() else { throw GenerationError(message: "no image") }
        return image
    }

    /// One normalized `mwg-rs` region: its center and size as fractions of the stored pixels.
    struct Region: Sendable {
        let name: String
        let x: Double
        let y: Double
        let w: Double
        let h: Double
    }

    /// ``asymmetricImage()`` as `type`, tagged `orientation`, with `regions` in `mwg-rs:Regions`.
    static func asymmetric(_ type: UTType, orientation: Int, regions: [Region] = [], in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("asymmetric-\(orientation)-\(UUID().uuidString)").appendingPathExtension(for: type)
        let metadata = try regions.isEmpty ? nil : regionMetadata(regions)

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw GenerationError(message: "no \(type.identifier) destination")
        }

        let options: [CFString: Any] = [kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 1]
        CGImageDestinationAddImageAndMetadata(destination, try asymmetricImage(), metadata, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { throw GenerationError(message: "\(type.identifier) did not encode") }

        return url
    }

    private static let regionsNamespace = "http://www.metadataworkinggroup.com/schemas/regions/"
    private static let areaNamespace = "http://ns.adobe.com/xmp/sType/Area#"
    private static let dimensionsNamespace = "http://ns.adobe.com/xap/1.0/sType/Dimensions#"

    static func regionMetadata(_ regions: [Region]) throws -> CGMutableImageMetadata {
        let metadata = CGImageMetadataCreateMutable()

        for (namespace, prefix) in [(regionsNamespace, "mwg-rs"), (areaNamespace, "stArea"), (dimensionsNamespace, "stDim")] {
            guard CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace as CFString, prefix as CFString, nil) else {
                throw GenerationError(message: "\(prefix) did not register")
            }
        }

        func tag(_ namespace: String, _ prefix: String, _ name: String, _ type: CGImageMetadataType, _ value: CFTypeRef) throws -> CGImageMetadataTag {
            guard let tag = CGImageMetadataTagCreate(namespace as CFString, prefix as CFString, name as CFString, type, value) else {
                throw GenerationError(message: "no \(name) tag")
            }
            return tag
        }

        func string(_ namespace: String, _ prefix: String, _ name: String, _ value: String) throws -> CGImageMetadataTag {
            try tag(namespace, prefix, name, .string, value as CFString)
        }

        let list = try regions.map { region in
            let area: [String: CGImageMetadataTag] = try [
                "x": string(areaNamespace, "stArea", "x", String(region.x)),
                "y": string(areaNamespace, "stArea", "y", String(region.y)),
                "w": string(areaNamespace, "stArea", "w", String(region.w)),
                "h": string(areaNamespace, "stArea", "h", String(region.h)),
                "unit": string(areaNamespace, "stArea", "unit", "normalized"),
            ]
            let fields: [String: CGImageMetadataTag] = try [
                "Area": tag(regionsNamespace, "mwg-rs", "Area", .structure, area as CFDictionary),
                "Name": string(regionsNamespace, "mwg-rs", "Name", region.name),
                "Type": string(regionsNamespace, "mwg-rs", "Type", "Face"),
            ]
            return try tag(regionsNamespace, "mwg-rs", "Region", .structure, fields as CFDictionary)
        }

        let dimensions: [String: CGImageMetadataTag] = try [
            "w": string(dimensionsNamespace, "stDim", "w", String(asymmetricWidth)),
            "h": string(dimensionsNamespace, "stDim", "h", String(asymmetricHeight)),
            "unit": string(dimensionsNamespace, "stDim", "unit", "pixel"),
        ]
        let structure: [String: CGImageMetadataTag] = try [
            "AppliedToDimensions": tag(regionsNamespace, "mwg-rs", "AppliedToDimensions", .structure, dimensions as CFDictionary),
            "RegionList": tag(regionsNamespace, "mwg-rs", "RegionList", .arrayUnordered, list as CFArray),
        ]

        guard CGImageMetadataSetTagWithPath(
            metadata, nil, "mwg-rs:Regions" as CFString,
            try tag(regionsNamespace, "mwg-rs", "Regions", .structure, structure as CFDictionary)
        ) else { throw GenerationError(message: "regions did not set") }

        return metadata
    }

    /// The normalized regions `url` carries, by name, and its `AppliedToDimensions`.
    static func regions(_ url: URL) -> (regions: [String: Region], width: Int?, height: Int?) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        else { return ([:], nil, nil) }

        return regions(metadata)
    }

    static func regions(_ metadata: CGImageMetadata) -> (regions: [String: Region], width: Int?, height: Int?) {
        let list = "mwg-rs:Regions.mwg-rs:RegionList"

        func string(_ path: String) -> String? {
            CGImageMetadataCopyStringValueWithPath(metadata, nil, path as CFString) as String?
        }

        let count = CGImageMetadataCopyTagWithPath(metadata, nil, list as CFString)
            .flatMap { CGImageMetadataTagCopyValue($0) as? [Any] }?.count ?? 0
        var result: [String: Region] = [:]

        for index in 0 ..< count {
            let area = "\(list)[\(index)].mwg-rs:Area.stArea:"

            guard let name = string("\(list)[\(index)].mwg-rs:Name"),
                  let x = string(area + "x").flatMap(Double.init),
                  let y = string(area + "y").flatMap(Double.init),
                  let w = string(area + "w").flatMap(Double.init),
                  let h = string(area + "h").flatMap(Double.init)
            else { continue }

            result[name] = Region(name: name, x: x, y: y, w: w, h: h)
        }

        let dimensions = "mwg-rs:Regions.mwg-rs:AppliedToDimensions.stDim:"
        return (result, string(dimensions + "w").flatMap(Int.init), string(dimensions + "h").flatMap(Int.init))
    }

    /// A gain-mapped `type` tagged `orientation`, its map replaced by a checkerboard of 12 × 8 squares so a map
    /// carried uncropped is told apart from one cropped. Built from Core Image's HEIC or JPEG.
    @available(macOS 15, iOS 18, *)
    static func checkerMapped(_ type: UTType, formats: [GainMapFormat], orientation: Int, in directory: URL) throws -> URL {
        let encoded: UTType = type == .jpeg ? .jpeg : .heic
        let intermediate = directory.appendingPathComponent("intermediate-\(UUID().uuidString)").appendingPathExtension(for: encoded)
        try writeGainMapped(CIImage(cgImage: try songbird()), type: encoded, format: .iso, to: intermediate)

        let name = formats.map(\.rawValue).joined(separator: "-")
        let url = directory.appendingPathComponent("checker-\(name)-\(orientation)-\(UUID().uuidString)").appendingPathExtension(for: type)

        guard let source = CGImageSourceCreateWithURL(intermediate as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              var map = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap) as? [String: Any],
              let description = map[kCGImageAuxiliaryDataInfoDataDescription as String] as? [String: Any],
              let width = description["Width"] as? Int,
              let height = description["Height"] as? Int,
              let bytesPerRow = description["BytesPerRow"] as? Int,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw GenerationError(message: "no gain-mapped \(type.identifier)") }

        var data = [UInt8](repeating: 0, count: bytesPerRow * height)

        for y in 0 ..< height {
            for x in 0 ..< width {
                data[y * bytesPerRow + x] = (x * 12 / width + y * 8 / height) % 2 == 0 ? 40 : 230
            }
        }

        map[kCGImageAuxiliaryDataInfoData as String] = Data(data)

        let options: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        CGImageDestinationAddImageAndMetadata(destination, image, CGImageSourceCopyMetadataAtIndex(source, 0, nil), options as CFDictionary)
        for format in formats {
            CGImageDestinationAddAuxiliaryDataInfo(destination, format.auxiliaryType, map as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else { throw GenerationError(message: "\(type.identifier) did not encode") }

        return url
    }
}
