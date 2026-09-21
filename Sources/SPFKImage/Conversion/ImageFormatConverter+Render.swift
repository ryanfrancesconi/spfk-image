// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension ImageFormatConverter {
    /// Decodes upright, applies the source's adjustments at full size and scales to `size`, in the source's color space
    /// when it is RGB or gray and sRGB otherwise.
    func renderedImage(_ imageSource: CGImageSource, index: Int, properties: [String: Any], size: PixelSize?) throws -> CGImage {
        let upright = CIImage(cgImageSource: imageSource, index: index, options: [.applyOrientationProperty: true])
        let decoded = source.adjustments.map { ImageAdjustmentRenderer.apply($0, to: upright) } ?? upright

        // Core Image reports a CMYK source as RGB, so ImageIO's color model decides whose space is kept.
        let colorModel = properties[kCGImagePropertyColorModel as String] as? String
        let keepsSourceSpace = [kCGImagePropertyColorModelRGB as String, kCGImagePropertyColorModelGray as String]
            .contains(colorModel ?? kCGImagePropertyColorModelRGB as String)

        guard let colorSpace = (keepsSourceSpace ? upright.colorSpace : nil) ?? CGColorSpace(name: CGColorSpace.sRGB),
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

        return cgImage
    }

    /// Writes ``renderedImage(_:index:properties:size:)`` with orientation 1, the scheme's metadata and each gain map
    /// turned to match.
    func render(
        _ imageSource: CGImageSource,
        index: Int,
        properties: [String: Any],
        to url: URL,
        type: UTType,
        size: PixelSize?
    ) throws {
        let cgImage = try renderedImage(imageSource, index: index, properties: properties, size: size)

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ImageConversionError.unwritableType(type.identifier)
        }

        var options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: source.options.quality,
            kCGImagePropertyOrientation: 1,
        ]

        if !Self.carriesMetadata(type) {
            // A type that keeps no metadata can refuse the image when metadata comes with it, as HEIF sequences do.
            CGImageDestinationAddImageAndMetadata(destination, cgImage, nil, options as CFDictionary)
        } else if source.options.metadata == .stripAll {
            // Properties rather than metadata, which cannot name Apple's headroom keys alone.
            options.merge(Self.headroomProperties(properties)) { $1 }
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        } else {
            let metadata = CGImageSourceCopyMetadataAtIndex(imageSource, index, nil).flatMap { CGImageMetadataCreateMutableCopy($0) }

            if let metadata {
                CGImageMetadataSetValueMatchingImageProperty(
                    metadata, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, 1 as CFNumber
                )
            }

            if source.options.metadata == .copyAllExceptLocation {
                options[kCGImageMetadataShouldExcludeGPS] = true

                // The exclusion leaves a GPS field in the `exifEX` namespace.
                if let metadata { Self.removeLocation(from: metadata) }
            }

            CGImageDestinationAddImageAndMetadata(destination, cgImage, metadata, options as CFDictionary)
        }

        if Self.gainMapTypeIdentifiers.contains(type.identifier) {
            Self.addGainMaps(
                from: imageSource,
                index: index,
                orientation: properties[kCGImagePropertyOrientation as String] as? Int ?? 1,
                to: destination
            )
        }

        guard CGImageDestinationFinalize(destination) else { throw ImageConversionError.encodeFailed(type.identifier) }
    }
}
