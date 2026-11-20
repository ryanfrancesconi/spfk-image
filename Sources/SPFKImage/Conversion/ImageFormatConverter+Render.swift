// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import SPFKBase
import UniformTypeIdentifiers

extension ImageFormatConverter {
    /// Decodes upright, applies the source's crop, adjustments and orientation at full size and scales to `size`,
    /// in the source's color space when it is RGB or gray and sRGB otherwise. An adjusted RAW is developed
    /// through ``RAWDevelop`` before the crop.
    func renderedImage(_ imageSource: CGImageSource, index: Int, properties: [String: Any], size: PixelSize?) throws -> CGImage {
        let upright = CIImage(cgImageSource: imageSource, index: index, options: [.applyOrientationProperty: true])
        let adjusted: CIImage

        if source.developsRAW, RAWDevelop.isRAW(imageSource) {
            // The develop reads the file's main image. Its output is upright with `upright`'s extent.
            let developed: RAWDevelop.Developed
            let adjustments = source.adjustments ?? ImageAdjustmentDescription()

            do {
                do {
                    developed = try RAWDevelop.develop(
                        contentsOf: source.input,
                        adjustments: adjustments,
                        decoderVersion: source.rawDecoderVersion
                    )
                } catch let RAWDevelopError.unsupportedDecoderVersion(version) {
                    Log.error(
                        "\(source.input.lastPathComponent) was adjusted with RAW decoder version \(version), which this Mac does not offer; using the default"
                    )
                    developed = try RAWDevelop.develop(contentsOf: source.input, adjustments: adjustments)
                }
            } catch {
                Log.error("RAW develop failed for \(source.input.lastPathComponent): \(error)")
                throw ImageConversionError.renderFailed
            }

            adjusted = ImageAdjustmentRenderer.apply(developed.remaining, to: source.crop.apply(to: developed.image))
        } else {
            let cropped = source.crop.apply(to: upright)
            adjusted = source.adjustments.map { ImageAdjustmentRenderer.apply($0, to: cropped) } ?? cropped
        }

        let decoded = source.orientation.apply(to: adjusted)

        // Core Image reports a CMYK source as RGB, so ImageIO's color model decides whose space is kept.
        let keepsSourceSpace = ImageFileWriting.isRGBOrGray(colorModel: properties[kCGImagePropertyColorModel as String] as? String)

        guard let colorSpace = (keepsSourceSpace ? upright.colorSpace : nil) ?? CGColorSpace(name: CGColorSpace.sRGB),
              let format = ImageFileWriting.fileFormat(
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
            let metadata = try Self.copiedMetadata(imageSource, index: index, overlay: overlayMetadata())

            if let metadata {
                CGImageMetadataSetValueMatchingImageProperty(
                    metadata, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, 1 as CFNumber
                )
                fitMetadata(metadata, properties: properties, written: PixelSize(width: cgImage.width, height: cgImage.height))
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
                before: Self.fileOrientation(properties),
                crop: source.crop,
                orientation: source.orientation,
                to: destination
            )
        }

        guard CGImageDestinationFinalize(destination) else { throw ImageConversionError.encodeFailed(type.identifier) }
    }

    static func fileOrientation(_ properties: [String: Any]) -> OrientationEdit {
        OrientationEdit(rawValue: properties[kCGImagePropertyOrientation as String] as? Int ?? 1) ?? .up
    }

    /// The written size in EXIF when it differs from the source's displayed size, and the face regions moved
    /// with the pixels whenever they were turned or cropped.
    func fitMetadata(_ metadata: CGMutableImageMetadata, properties: [String: Any], written: PixelSize) {
        guard let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int
        else { return }

        let before = Self.fileOrientation(properties)
        let displayed = Self.displayedSize(width: width, height: height, orientation: source.displayedOrientation(fileOrientation: before.rawValue))

        if written != displayed {
            Self.setPixelDimensions(metadata, width: written.width, height: written.height)
        }

        remapRegions(metadata, properties: properties, written: written)
    }

    /// The face regions moved with pixels that were drawn upright from a tagged file, cropped or turned.
    func remapRegions(_ metadata: CGMutableImageMetadata, properties: [String: Any], written: PixelSize) {
        let before = Self.fileOrientation(properties)

        guard let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              !before.isIdentity || !source.crop.isIdentity || !source.orientation.isIdentity
        else { return }

        Self.remapRegions(
            metadata, storedWidth: width, storedHeight: height, before: before, crop: source.crop, after: source.orientation,
            writtenWidth: written.width, writtenHeight: written.height
        )
    }
}
