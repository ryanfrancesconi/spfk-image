// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import ImageIO
import UniformTypeIdentifiers

extension ImageFormatConverter {
    /// ImageIO's own re-encode, followed where metadata is kept by a lossless rewrite restoring the XMP the
    /// re-encode drops.
    func transcode(
        _ imageSource: CGImageSource,
        index: Int,
        properties: [String: Any],
        to url: URL,
        type: UTType,
        maxPixelSize: Int?
    ) throws {
        let scheme = source.options.metadata

        let sourceMetadata = scheme == .stripAll || !Self.mergeTypeIdentifiers.contains(type.identifier)
            ? nil
            : CGImageSourceCopyMetadataAtIndex(imageSource, index, nil)

        // A sibling in the conversion's own work directory.
        let encoded = sourceMetadata == nil
            ? url
            : url.deletingLastPathComponent().appending(component: "encoded-\(url.lastPathComponent)", directoryHint: .notDirectory)

        guard let destination = CGImageDestinationCreateWithURL(encoded as CFURL, type.identifier as CFString, 1, nil) else {
            throw ImageConversionError.unwritableType(type.identifier)
        }

        var options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: source.options.quality,
        ]

        if let maxPixelSize {
            options[kCGImageDestinationImageMaxPixelSize] = maxPixelSize
        }

        if Self.gainMapTypeIdentifiers.contains(type.identifier) {
            options[kCGImageDestinationPreserveGainMap] = true
        }

        switch scheme {
        case .copyAll:
            break

        case .copyAllExceptLocation:
            options[kCGImageMetadataShouldExcludeGPS] = true

        case .stripAll:
            options.merge(Self.strippingProperties(properties)) { $1 }
        }

        CGImageDestinationAddImageFromSource(destination, imageSource, index, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { throw ImageConversionError.encodeFailed(type.identifier) }

        guard let sourceMetadata else { return }

        try merge(sourceMetadata, from: encoded, into: url, type: type)
    }

    /// Lossless for a lossless output, and keeps every field the source's metadata holds.
    func rewrap(_ imageSource: CGImageSource, index: Int, properties: [String: Any], to url: URL, type: UTType) throws {
        guard let image = CGImageSourceCreateImageAtIndex(imageSource, index, nil) else {
            throw ImageConversionError.renderFailed
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ImageConversionError.unwritableType(type.identifier)
        }

        var options: [CFString: Any] = [
            kCGImagePropertyOrientation: properties[kCGImagePropertyOrientation as String] as? Int ?? 1,
        ]

        if source.options.metadata == .copyAllExceptLocation {
            options[kCGImageMetadataShouldExcludeGPS] = true
        }

        CGImageDestinationAddImageAndMetadata(
            destination, image, CGImageSourceCopyMetadataAtIndex(imageSource, index, nil), options as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else { throw ImageConversionError.encodeFailed(type.identifier) }
    }

    /// Leaves the pixels, gain map and orientation as the transcode wrote them.
    private func merge(_ metadata: CGImageMetadata, from encoded: URL, into url: URL, type: UTType) throws {
        let keepsLocation = source.options.metadata != .copyAllExceptLocation

        guard let encodedSource = CGImageSourceCreateWithURL(encoded as CFURL, nil),
              let merged = Self.mergeMetadata(metadata),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw ImageConversionError.encodeFailed(type.identifier) }

        var options: [CFString: Any] = [
            kCGImageDestinationMetadata: merged,
            kCGImageDestinationMergeMetadata: true,
        ]

        if !keepsLocation {
            options[kCGImageMetadataShouldExcludeGPS] = true
        }

        guard CGImageDestinationCopyImageSource(destination, encodedSource, options as CFDictionary, nil) else {
            throw ImageConversionError.encodeFailed(type.identifier)
        }
    }
}
