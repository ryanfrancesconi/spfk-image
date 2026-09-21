// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension ImageFormatConverter {
    enum Route: Equatable {
        /// `CGImageDestinationAddImageFromSource`: ImageIO re-encodes and carries the metadata itself.
        case transcode
        /// ImageIO's own decode, unrotated, written with the source's metadata and orientation tag.
        case rewrap
        /// Decoded upright and scaled through Core Image, then written with orientation 1.
        case render
    }

    struct PixelSize: Equatable {
        var width: Int
        var height: Int
    }

    static let context = CIContext()

    static func route(
        to type: UTType,
        orientation: Int,
        colorModel: String?,
        resizes: Bool,
        adjusts: Bool,
        metadata: ImageMetadataCopyScheme
    ) -> Route {
        // Only a decode can take the adjustments.
        if adjusts {
            return .render
        }

        // A transcode into JPEG or TIFF keeps CMYK as CMYK.
        if let colorModel,
           colorModel != kCGImagePropertyColorModelRGB as String,
           colorModel != kCGImagePropertyColorModelGray as String
        {
            return .render
        }

        // AVIF drops the orientation tag, and refuses the metadata rewrite a transcode needs.
        if type.identifier == avifIdentifier {
            return .render
        }

        // GIF writes the orientation tag over pixels it has already rotated.
        if orientation != 1, type.identifier == UTType.gif.identifier {
            return .render
        }

        // A resize into JPEG strips EXIF and enlarges a smaller source; into PNG or TIFF it adds alpha.
        if resizes, type.identifier != UTType.heic.identifier {
            return .render
        }

        guard metadata != .stripAll else { return .transcode }

        // Rewriting TIFF metadata loses the EXIF time zone offsets.
        if type.identifier == UTType.tiff.identifier {
            return .rewrap
        }

        if carriesMetadata(type), !mergeTypeIdentifiers.contains(type.identifier) {
            return .render
        }

        return .transcode
    }

    static func displayedSize(width: Int, height: Int, orientation: Int) -> PixelSize {
        (5 ... 8).contains(orientation)
            ? PixelSize(width: height, height: width)
            : PixelSize(width: width, height: height)
    }

    /// `size` scaled so its longest edge is `maxPixelSize`, or `nil` when it is already no longer.
    static func limitedSize(_ size: PixelSize, maxPixelSize: Int?) -> PixelSize? {
        let longest = max(size.width, size.height)
        guard let maxPixelSize, longest > maxPixelSize else { return nil }

        let scale = Double(maxPixelSize) / Double(longest)

        return PixelSize(
            width: max(1, Int((Double(size.width) * scale).rounded())),
            height: max(1, Int((Double(size.height) * scale).rounded()))
        )
    }

    func write(to url: URL, type: UTType) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source.input as CFURL, nil),
              CGImageSourceGetType(imageSource) != nil
        else { throw ImageConversionError.unreadable(source.input) }

        let index = CGImageSourceGetPrimaryImageIndex(imageSource)

        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int
        else { throw ImageConversionError.unreadable(source.input) }

        let orientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1
        let displayed = Self.displayedSize(width: width, height: height, orientation: orientation)
        let limited = Self.limitedSize(displayed, maxPixelSize: source.options.maxPixelSize)

        if let encoder = formats.encoder(for: type) {
            let written = limited ?? displayed

            if let maxPixelSize = encoder.maxPixelSize, max(written.width, written.height) > maxPixelSize {
                throw ImageConversionError.exceedsMaxPixelSize(type.identifier, maxPixelSize)
            }

            try encode(imageSource, index: index, properties: properties, to: url, encoder: encoder, size: limited)
            try Self.verify(url, displays: written, tolerance: limited == nil ? 0 : 1)
            return
        }

        let route = Self.route(
            to: type,
            orientation: orientation,
            colorModel: properties[kCGImagePropertyColorModel as String] as? String,
            resizes: limited != nil,
            adjusts: source.hasAdjustments,
            metadata: source.options.metadata
        )

        switch route {
        case .transcode:
            do {
                // Only a limit the image exceeds: JPEG enlarges a smaller image to meet it.
                try transcode(
                    imageSource, index: index, properties: properties, to: url, type: type,
                    maxPixelSize: limited == nil ? nil : source.options.maxPixelSize
                )
            } catch ImageConversionError.encodeFailed {
                // ImageIO cannot transcode some pairs, HEIC into a HEIF sequence among them.
                try render(imageSource, index: index, properties: properties, to: url, type: type, size: limited)
            }

        case .rewrap:
            do {
                try rewrap(imageSource, index: index, properties: properties, to: url, type: type)
            } catch ImageConversionError.encodeFailed {
                try render(imageSource, index: index, properties: properties, to: url, type: type, size: limited)
            }

        case .render:
            try render(imageSource, index: index, properties: properties, to: url, type: type, size: limited)
        }

        try Self.verify(url, displays: limited ?? displayed, tolerance: limited == nil ? 0 : 1)
    }

    static func verify(_ url: URL, displays expected: PixelSize, tolerance: Int) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int
        else { throw ImageConversionError.readBackMismatch }

        let displayed = displayedSize(
            width: width,
            height: height,
            orientation: properties[kCGImagePropertyOrientation as String] as? Int ?? 1
        )

        guard abs(displayed.width - expected.width) <= tolerance,
              abs(displayed.height - expected.height) <= tolerance
        else { throw ImageConversionError.readBackMismatch }
    }
}
