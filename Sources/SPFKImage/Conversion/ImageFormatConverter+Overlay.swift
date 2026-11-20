// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import ImageIO
import SPFKBase

extension ImageFormatConverter {
    /// ``ImageConversionSource/overlayXMP`` parsed; nil when there is none.
    func overlayMetadata() throws -> CGImageMetadata? {
        guard let xmp = source.overlayXMP else { return nil }

        guard let metadata = CGImageMetadataCreateFromXMPData(Data(xmp.utf8) as CFData) else {
            throw ImageConversionError.unreadableOverlayXMP
        }

        return metadata
    }

    /// The input's metadata with `overlay` laid over it; nil when there is neither.
    static func copiedMetadata(_ imageSource: CGImageSource, index: Int, overlay: CGImageMetadata?) -> CGMutableImageMetadata? {
        let copied = CGImageSourceCopyMetadataAtIndex(imageSource, index, nil).flatMap { CGImageMetadataCreateMutableCopy($0) }

        guard let overlay else { return copied }

        let metadata = copied ?? CGImageMetadataCreateMutable()
        lay(overlay, over: metadata)
        return metadata
    }

    /// Replaces each top-level property of `metadata` that `overlay` holds.
    ///
    /// An emptied array or language alternative replaces the property too, which clears it, in a merge as well:
    /// ImageIO refuses `kCFNull` there for HEIC and PNG. An empty simple property cannot clear, since ImageIO
    /// drops it when it parses XMP.
    static func lay(_ overlay: CGImageMetadata, over metadata: CGMutableImageMetadata) {
        var tags: [(path: CFString, tag: CGImageMetadataTag)] = []

        CGImageMetadataEnumerateTagsUsingBlock(overlay, nil, nil) { path, tag in
            // ImageIO's own markers, such as `iio:hasXMP`.
            if CGImageMetadataTagCopyPrefix(tag) as String? != "iio" {
                tags.append((path, tag))
            }

            return true
        }

        for (path, tag) in tags {
            if let namespace = CGImageMetadataTagCopyNamespace(tag), let prefix = CGImageMetadataTagCopyPrefix(tag) {
                // False when the prefix is already registered, which is no failure.
                _ = CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, prefix, nil)
            }

            if !CGImageMetadataSetTagWithPath(metadata, nil, path, tag) {
                Log.error("Couldn't apply \(path) from the overlay to the converted image's metadata")
            }
        }
    }
}
