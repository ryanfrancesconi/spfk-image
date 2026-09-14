// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import ImageIO
import UniformTypeIdentifiers

extension ImageFormatConverter {
    /// Every type identifier ImageIO can write on this system.
    public static let writableTypeIdentifiers: Set<String> =
        Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])

    /// The types offered as a conversion's output: every image type ImageIO writes except GPU textures and
    /// icons. Types that keep metadata come first, each group ordered by name.
    public static let outputTypes: [UTType] = writableTypeIdentifiers
        .compactMap { UTType($0) }
        .filter {
            $0.conforms(to: .image) && $0.preferredFilenameExtension != nil
                && !nonPhotoTypeIdentifiers.contains($0.identifier)
        }
        .sorted { lhs, rhs in
            guard carriesMetadata(lhs) == carriesMetadata(rhs) else { return carriesMetadata(lhs) }
            return name(of: lhs).localizedStandardCompare(name(of: rhs)) == .orderedAscending
        }

    /// Whether ImageIO honors ``ImageConversionOptions/quality`` when writing `type`.
    public static func usesQuality(_ type: UTType) -> Bool {
        lossyTypeIdentifiers.contains(type.identifier)
    }

    /// Whether a converted file of `type` keeps the source's EXIF, GPS and XMP. `false` for a type not known to.
    public static func carriesMetadata(_ type: UTType) -> Bool {
        metadataTypeIdentifiers.contains(type.identifier)
    }

    static let avifIdentifier = "public.avif"

    static let nonPhotoTypeIdentifiers: Set<String> = [
        // GPU textures
        "com.apple.atx", "com.microsoft.dds", "org.khronos.astc", "org.khronos.ktx", "org.khronos.ktx2", "public.pvr",
        // Icons
        "com.apple.icns", "com.microsoft.ico",
    ]

    static let lossyTypeIdentifiers: Set<String> = [
        UTType.jpeg.identifier, UTType.heic.identifier, "public.heics", avifIdentifier, "public.jpeg-2000",
    ]

    static let metadataTypeIdentifiers: Set<String> = [
        UTType.jpeg.identifier, UTType.heic.identifier, avifIdentifier, UTType.png.identifier,
        UTType.tiff.identifier, UTType.gif.identifier, "com.adobe.photoshop-image",
    ]

    /// Types whose metadata ImageIO rewrites losslessly. A transcode keeps only a few XMP namespaces, so it
    /// keeps the rest only into these.
    ///
    /// The rewrite drops the EXIF time zone offsets from PSD, which keeps XMP no other way. TIFF rewraps instead.
    static let mergeTypeIdentifiers: Set<String> = [
        UTType.jpeg.identifier, UTType.heic.identifier, UTType.png.identifier, "com.adobe.photoshop-image",
    ]

    /// Types that hold an HDR gain map.
    static let gainMapTypeIdentifiers: Set<String> = [
        UTType.jpeg.identifier, UTType.heic.identifier, avifIdentifier,
    ]

    private static func name(of type: UTType) -> String {
        type.localizedDescription ?? type.identifier
    }
}
