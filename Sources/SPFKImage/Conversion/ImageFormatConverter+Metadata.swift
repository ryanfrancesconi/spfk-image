// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import ImageIO

extension ImageFormatConverter {
    /// Every property dictionary holding descriptive, technical or location metadata. The structural ones (JFIF,
    /// GIF, HEIF, PNG's color fields) stay.
    static var metadataDictionaryKeys: [CFString] {
        [
            kCGImagePropertyExifDictionary, kCGImagePropertyExifAuxDictionary, kCGImagePropertyGPSDictionary,
            kCGImagePropertyIPTCDictionary, kCGImagePropertyTIFFDictionary, kCGImageProperty8BIMDictionary,
            kCGImagePropertyDNGDictionary, kCGImagePropertyCIFFDictionary, kCGImagePropertyRawDictionary,
            kCGImagePropertyMakerAppleDictionary, kCGImagePropertyMakerCanonDictionary, kCGImagePropertyMakerFujiDictionary,
            kCGImagePropertyMakerMinoltaDictionary, kCGImagePropertyMakerNikonDictionary,
            kCGImagePropertyMakerOlympusDictionary, kCGImagePropertyMakerPentaxDictionary,
        ]
    }

    static var pngTextKeys: [CFString] {
        [
            kCGImagePropertyPNGTitle, kCGImagePropertyPNGAuthor, kCGImagePropertyPNGDescription,
            kCGImagePropertyPNGCopyright, kCGImagePropertyPNGComment, kCGImagePropertyPNGCreationTime,
            kCGImagePropertyPNGModificationTime, kCGImagePropertyPNGSoftware, kCGImagePropertyPNGDisclaimer,
            kCGImagePropertyPNGWarning,
        ]
    }

    /// The Apple maker note keys an older iPhone photo's HDR headroom is computed from. Without them its gain map
    /// displays as SDR.
    static let appleHeadroomKeys: Set<String> = ["33", "48"]

    /// Transcode options removing every metadata property `properties` holds, Apple's headroom keys excepted.
    ///
    /// Only what is present is named: removing a property the source lacks writes an empty one in its place.
    static func strippingProperties(_ properties: [String: Any]) -> [CFString: Any] {
        var options: [CFString: Any] = [kCGImageMetadataShouldExcludeXMP: true]

        for key in metadataDictionaryKeys where properties[key as String] != nil {
            options[key] = kCFNull
        }

        if let apple = properties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any] {
            options[kCGImagePropertyMakerAppleDictionary] = Dictionary(
                uniqueKeysWithValues: apple.keys.filter { !appleHeadroomKeys.contains($0) }.map { ($0, kCFNull as Any) }
            )
        }

        if let png = properties[kCGImagePropertyPNGDictionary as String] as? [String: Any] {
            let text = pngTextKeys.filter { png[$0 as String] != nil }

            if text.isNotEmpty {
                options[kCGImagePropertyPNGDictionary] = Dictionary(
                    uniqueKeysWithValues: text.map { ($0 as String, kCFNull as Any) }
                )
            }
        }

        return options
    }

    /// Apple's headroom keys alone, for a render that writes no other metadata.
    static func headroomProperties(_ properties: [String: Any]) -> [CFString: Any] {
        guard let apple = properties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any] else { return [:] }

        let kept = apple.filter { appleHeadroomKeys.contains($0.key) }
        return kept.isEmpty ? [:] : [kCGImagePropertyMakerAppleDictionary: kept]
    }

    /// The namespaces a transcode carries itself, from the camera's own EXIF and TIFF.
    static let cameraPrefixes: Set<String> = ["exif", "exifEX", "aux", "tiff"]

    /// The source's XMP outside ``cameraPrefixes``, for the lossless rewrite after a transcode.
    ///
    /// Rewriting the camera namespaces as well drops the EXIF time zone offsets from TIFF and PSD, and lets PNG take
    /// back the GPS a transcode excluded.
    static func mergeMetadata(_ metadata: CGImageMetadata) -> CGMutableImageMetadata? {
        guard let merged = CGImageMetadataCreateMutableCopy(metadata) else { return nil }

        var cameraPaths: [CFString] = []

        CGImageMetadataEnumerateTagsUsingBlock(merged, nil, nil) { path, tag in
            if Self.cameraPrefixes.contains(CGImageMetadataTagCopyPrefix(tag) as String? ?? "") {
                cameraPaths.append(path)
            }

            return true
        }

        for path in cameraPaths {
            CGImageMetadataRemoveTagWithPath(merged, nil, path)
        }

        return merged
    }
}
