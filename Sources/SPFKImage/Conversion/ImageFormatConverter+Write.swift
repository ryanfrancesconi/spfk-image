// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension ImageFormatConverter {
    enum Route: Equatable {
        /// `CGImageDestinationAddImageFromSource`: ImageIO re-encodes and carries the metadata itself.
        case transcode
        /// Decoded upright and scaled through Core Image, then written with orientation 1.
        case render
    }

    struct PixelSize: Equatable {
        var width: Int
        var height: Int
    }

    static let context = CIContext()

    static func route(to type: UTType, orientation: Int, colorModel: String?, resizes: Bool) -> Route {
        // A transcode into JPEG or TIFF keeps CMYK as CMYK.
        if let colorModel,
           colorModel != kCGImagePropertyColorModelRGB as String,
           colorModel != kCGImagePropertyColorModelGray as String
        {
            return .render
        }

        // AVIF drops the orientation tag, and GIF writes it over pixels it has already rotated.
        if orientation != 1, [avifIdentifier, UTType.gif.identifier].contains(type.identifier) {
            return .render
        }

        // A resize into JPEG strips EXIF and enlarges a smaller source; into PNG or TIFF it adds alpha.
        if resizes, ![UTType.heic.identifier, avifIdentifier].contains(type.identifier) {
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

        let route = Self.route(
            to: type,
            orientation: orientation,
            colorModel: properties[kCGImagePropertyColorModel as String] as? String,
            resizes: limited != nil
        )

        switch route {
        case .transcode:
            do {
                // Only a limit the image exceeds: JPEG enlarges a smaller image to meet it.
                try transcode(
                    imageSource, index: index, to: url, type: type,
                    maxPixelSize: limited == nil ? nil : source.options.maxPixelSize
                )
            } catch ImageConversionError.encodeFailed {
                // ImageIO cannot transcode some pairs, HEIC into a HEIF sequence among them.
                try render(imageSource, index: index, properties: properties, to: url, type: type, size: limited)
            }

        case .render:
            try render(imageSource, index: index, properties: properties, to: url, type: type, size: limited)
        }

        try Self.verify(url, displays: limited ?? displayed, tolerance: limited == nil ? 0 : 1)
    }

    private func transcode(_ imageSource: CGImageSource, index: Int, to url: URL, type: UTType, maxPixelSize: Int?) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
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

        CGImageDestinationAddImageFromSource(destination, imageSource, index, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { throw ImageConversionError.encodeFailed(type.identifier) }
    }

    private func render(
        _ imageSource: CGImageSource,
        index: Int,
        properties: [String: Any],
        to url: URL,
        type: UTType,
        size: PixelSize?
    ) throws {
        let decoded = CIImage(cgImageSource: imageSource, index: index, options: [.applyOrientationProperty: true])

        // Core Image reports a CMYK source as RGB, so ImageIO's color model decides whose space is kept.
        let colorModel = properties[kCGImagePropertyColorModel as String] as? String
        let keepsSourceSpace = [kCGImagePropertyColorModelRGB as String, kCGImagePropertyColorModelGray as String]
            .contains(colorModel ?? kCGImagePropertyColorModelRGB as String)

        guard let colorSpace = (keepsSourceSpace ? decoded.colorSpace : nil) ?? CGColorSpace(name: CGColorSpace.sRGB),
              let format = ImageAdjustmentRenderer.fileFormat(
                  model: colorSpace.model,
                  sixteenBit: (properties[kCGImagePropertyDepth as String] as? Int ?? 8) > 8,
                  alpha: properties[kCGImagePropertyHasAlpha as String] as? Bool ?? false
              )
        else { throw ImageConversionError.renderFailed }

        var image = decoded
        var bounds = decoded.extent

        if let size {
            let filter = CIFilter.lanczosScaleTransform()
            filter.inputImage = decoded
            filter.scale = Float(Double(size.height) / decoded.extent.height)
            filter.aspectRatio = Float((Double(size.width) / decoded.extent.width) / (Double(size.height) / decoded.extent.height))

            guard let scaled = filter.outputImage else { throw ImageConversionError.renderFailed }

            image = scaled
            bounds = CGRect(origin: scaled.extent.origin, size: CGSize(width: size.width, height: size.height))
        }

        guard let cgImage = Self.context.createCGImage(image, from: bounds, format: format, colorSpace: colorSpace, deferred: false) else {
            throw ImageConversionError.renderFailed
        }

        // A type that keeps no metadata can refuse the image when metadata comes with it, as HEIF sequences do.
        let metadata = Self.carriesMetadata(type)
            ? CGImageSourceCopyMetadataAtIndex(imageSource, index, nil).flatMap { CGImageMetadataCreateMutableCopy($0) }
            : nil

        if let metadata {
            CGImageMetadataSetValueMatchingImageProperty(
                metadata, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, 1 as CFNumber
            )
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ImageConversionError.unwritableType(type.identifier)
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: source.options.quality,
            kCGImagePropertyOrientation: 1,
        ]

        CGImageDestinationAddImageAndMetadata(destination, cgImage, metadata, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { throw ImageConversionError.encodeFailed(type.identifier) }
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
