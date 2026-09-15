// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension ImageFormatConverter {
    /// Renders upright at `size` and writes what `encoder` makes of it, with the scheme's metadata.
    func encode(
        _ imageSource: CGImageSource,
        index: Int,
        properties: [String: Any],
        to url: URL,
        encoder: any ImageFileEncoder,
        size: PixelSize?
    ) throws {
        let image = try renderedImage(imageSource, index: index, properties: properties, size: size)

        let metadata = try Self.encoderMetadata(
            imageSource,
            index: index,
            scheme: source.options.metadata,
            size: PixelSize(width: image.width, height: image.height),
            type: encoder.type
        )

        let data = try encoder.encode(
            ImageFileEncoderInput(image: image, quality: source.options.quality, exif: metadata.exif, xmp: metadata.xmp)
        )

        try data.write(to: url)
    }

    /// The source's metadata as an EXIF block and an XMP packet, stating orientation 1 and `size`.
    static func encoderMetadata(
        _ imageSource: CGImageSource,
        index: Int,
        scheme: ImageMetadataCopyScheme,
        size: PixelSize,
        type: UTType
    ) throws -> (exif: Data?, xmp: Data?) {
        guard scheme != .stripAll,
              let sourceMetadata = CGImageSourceCopyMetadataAtIndex(imageSource, index, nil),
              let metadata = CGImageMetadataCreateMutableCopy(sourceMetadata)
        else { return (nil, nil) }

        let values: [(dictionary: CFString, key: CFString, value: Int)] = [
            (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, 1),
            (kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelXDimension, size.width),
            (kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelYDimension, size.height),
        ]

        for item in values {
            guard CGImageMetadataSetValueMatchingImageProperty(metadata, item.dictionary, item.key, item.value as CFNumber) else {
                throw ImageConversionError.encodeFailed(type.identifier)
            }
        }

        if scheme == .copyAllExceptLocation {
            removeLocation(from: metadata)
        }

        guard let xmp = CGImageMetadataCreateXMPData(metadata, nil) as Data? else {
            throw ImageConversionError.encodeFailed(type.identifier)
        }

        return try (exifBlock(metadata, type: type), xmp)
    }

    /// Removes the GPS tags, which ImageIO keeps in the EXIF namespace.
    static func removeLocation(from metadata: CGMutableImageMetadata) {
        var paths: [CFString] = []

        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, tag in
            if CGImageMetadataTagCopyNamespace(tag) as String? == kCGImageMetadataNamespaceExif as String,
               (CGImageMetadataTagCopyName(tag) as String?)?.hasPrefix("GPS") == true
            {
                paths.append(path)
            }

            return true
        }

        for path in paths {
            CGImageMetadataRemoveTagWithPath(metadata, nil, path)
        }
    }

    /// The EXIF block ImageIO writes into a JPEG carrying `metadata`, or `nil` when `metadata` holds no EXIF field.
    ///
    /// Rewrites a placeholder losslessly: encoding the placeholder with `metadata` would state its own pixel size.
    static func exifBlock(_ metadata: CGImageMetadata, type: UTType) throws -> Data? {
        let jpeg = NSMutableData()

        guard let placeholder = CGImageSourceCreateWithData(placeholderJPEG as CFData, nil),
              let destination = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw ImageConversionError.encodeFailed(type.identifier) }

        let options: [CFString: Any] = [kCGImageDestinationMetadata: metadata, kCGImageDestinationMergeMetadata: false]

        guard CGImageDestinationCopyImageSource(destination, placeholder, options as CFDictionary, nil) else {
            throw ImageConversionError.encodeFailed(type.identifier)
        }

        return exifPayload(ofJPEG: jpeg as Data)
    }

    /// The TIFF structure after `Exif\0\0` in the first APP1 segment holding one, before the scan starts.
    static func exifPayload(ofJPEG data: Data) -> Data? {
        let bytes = [UInt8](data)
        let exifHeader: [UInt8] = [0x45, 0x78, 0x69, 0x66, 0, 0]

        guard bytes.starts(with: [0xFF, 0xD8]) else { return nil }

        var offset = 2

        while offset + 4 <= bytes.count, bytes[offset] == 0xFF {
            let marker = bytes[offset + 1]
            let end = offset + 2 + (Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3]))

            guard marker != 0xDA, end <= bytes.count else { return nil }

            let payload = offset + 4

            if marker == 0xE1, end - payload > exifHeader.count, Array(bytes[payload ..< payload + exifHeader.count]) == exifHeader {
                return Data(bytes[(payload + exifHeader.count) ..< end])
            }

            offset = end
        }

        return nil
    }

    /// A 1×1 JPEG with no metadata.
    static let placeholderJPEG: Data = {
        let data = NSMutableData()

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ),
              let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return Data() }

        CGImageDestinationAddImage(destination, image, nil)

        return CGImageDestinationFinalize(destination) ? data as Data : Data()
    }()
}
