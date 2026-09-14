// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Sources for ``ImageFormatConverterMetadataTests``, generated from `songbird.jpg` into a directory the caller owns.
enum ConversionFixtures {
    typealias GenerationError = AdjustmentFileFixtures.GenerationError

    static let timeZoneOffset = "-07:00"
    static let labelColor = "Red"
    static let altText = "A songbird on a branch"
    static let finderTags = ["Converted", "Red\n6"]

    /// A JPEG tagged with `orientation`, a capture date and time zone, GPS, `dc:subject`, and two TorchTag fields
    /// ImageIO's own transcode drops: `photoshop:LabelColor` and `Iptc4xmpCore:AltTextAccessibility`.
    static func fields(orientation: Int, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("fields-\(orientation).jpg")
        let metadata = CGImageMetadataCreateMutable()

        func set(_ dictionary: CFString, _ key: CFString, _ value: CFTypeRef) throws {
            guard CGImageMetadataSetValueMatchingImageProperty(metadata, dictionary, key, value) else {
                throw GenerationError(message: "\(key) could not be set")
            }
        }

        func tag(_ namespace: CFString, _ prefix: CFString, _ name: String, _ type: CGImageMetadataType, _ value: CFTypeRef) throws {
            guard CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, prefix, nil),
                  let tag = CGImageMetadataTagCreate(namespace, prefix, name as CFString, type, value),
                  CGImageMetadataSetTagWithPath(metadata, nil, "\(prefix):\(name)" as CFString, tag)
            else { throw GenerationError(message: "\(prefix):\(name) could not be set") }
        }

        try set(kCGImagePropertyExifDictionary, kCGImagePropertyExifDateTimeOriginal, AdjustmentFileFixtures.captureDate as CFString)
        try set(kCGImagePropertyExifDictionary, kCGImagePropertyExifOffsetTimeOriginal, timeZoneOffset as CFString)
        try set(kCGImagePropertyGPSDictionary, kCGImagePropertyGPSLatitude, AdjustmentFileFixtures.latitude as CFNumber)
        try set(kCGImagePropertyGPSDictionary, kCGImagePropertyGPSLatitudeRef, "N" as CFString)

        try tag(
            kCGImageMetadataNamespaceDublinCore, kCGImageMetadataPrefixDublinCore, "subject",
            .arrayUnordered, AdjustmentFileFixtures.keywords as CFArray
        )
        try tag(kCGImageMetadataNamespacePhotoshop, kCGImageMetadataPrefixPhotoshop, "LabelColor", .string, labelColor as CFString)
        try tag(
            kCGImageMetadataNamespaceIPTCCore, kCGImageMetadataPrefixIPTCCore, "AltTextAccessibility",
            .alternateText, ["x-default": altText] as CFDictionary
        )

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw GenerationError(message: "no JPEG destination")
        }

        try CGImageDestinationAddImageAndMetadata(
            destination, AdjustmentFileFixtures.songbird(), metadata, [kCGImagePropertyOrientation: orientation] as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else { throw GenerationError(message: "JPEG did not encode") }

        return url
    }

    /// ``AdjustmentFileFixtures/gainMapped(_:in:)`` as HEIC, tagged with `orientation` and its pixels and gain map
    /// left as stored.
    static func rotatedGainMap(orientation: Int, in directory: URL) throws -> URL {
        let upright = try AdjustmentFileFixtures.gainMapped(.heic, in: directory)
        let url = directory.appendingPathComponent("gain-map-\(orientation).heic")

        guard let source = CGImageSourceCreateWithURL(upright as CFURL, nil),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil)
        else { throw GenerationError(message: "no HEIC source or destination") }

        let options: [CFString: Any] = [kCGImageDestinationPreserveGainMap: true, kCGImagePropertyOrientation: orientation]
        CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { throw GenerationError(message: "HEIC did not encode") }

        return url
    }
}
