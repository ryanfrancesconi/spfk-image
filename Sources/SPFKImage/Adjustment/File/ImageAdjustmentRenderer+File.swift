// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import ImageIO
import SPFKBase

/// What ``ImageAdjustmentRenderer/renderFile(_:orientation:source:destination:quality:stage:)`` is doing. A Core
/// Image render reports no fraction of its own, so the stage is the only progress it has.
public enum ImageRenderStage: Sendable {
    case rendering
    case encoding
    case verifying
}

extension ImageAdjustmentRenderer {
    /// JPEG and HEIC encode quality for a rendered file.
    public static let defaultFileQuality: Double = 0.9

    /// Renders `adjustments` into a new file at `destination`, in the source's own format.
    ///
    /// Crops and adjusts the source's unoriented pixels and writes them with its metadata, its orientation tag
    /// with `orientation` performed, and every auxiliary image (gain maps, depth, mattes) carried unchanged, or
    /// for a crop, the gain maps cropped and the rest dropped. `crop` is in the displayed picture, before
    /// `orientation`. A format that cannot store an orientation (AVIF) is written upright, with orientation 1,
    /// and its gain maps turned to match. `destination` must not exist, and exists afterwards only if this
    /// returns; `source` is never written.
    /// `stage` is called as each stage begins, and not after a throw. Waits for a ``BlockingCallLimiter`` slot,
    /// since an AV1 encode blocks its thread.
    public func renderFile(
        _ adjustments: ImageAdjustmentDescription,
        orientation: OrientationEdit = .up,
        crop: CropEdit = CropEdit(),
        source: URL,
        destination: URL,
        quality: Double = defaultFileQuality,
        stage: (@Sendable (ImageRenderStage) -> Void)? = nil
    ) async throws {
        try await BlockingCallLimiter.shared.run {
            try Task.checkCancellation()

            try renderFile(
                adjustments, orientation: orientation, crop: crop, source: source, destination: destination,
                quality: quality, expectedOrientation: nil, stage: stage
            )
        }
    }

    /// `expectedOrientation` replaces the orientation the read-back requires, so a test can force a mismatch.
    func renderFile(
        _ adjustments: ImageAdjustmentDescription,
        orientation: OrientationEdit = .up,
        crop: CropEdit = CropEdit(),
        source: URL,
        destination: URL,
        quality: Double,
        expectedOrientation: Int?,
        stage: (@Sendable (ImageRenderStage) -> Void)? = nil
    ) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ImageAdjustmentRenderError.destinationExists
        }

        do {
            let written = try autoreleasepool {
                try write(
                    adjustments, orientation: orientation, crop: crop, source: source, destination: destination,
                    quality: quality, stage: stage
                )
            }

            stage?(.verifying)

            try ImageFileWriting.verify(
                destination,
                orientation: expectedOrientation ?? written.orientation,
                width: written.width,
                height: written.height
            )
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private struct Geometry {
        let orientation: Int
        let width: Int
        let height: Int
    }

    private func write(
        _ adjustments: ImageAdjustmentDescription,
        orientation: OrientationEdit,
        crop: CropEdit,
        source url: URL,
        destination: URL,
        quality: Double,
        stage: (@Sendable (ImageRenderStage) -> Void)?
    ) throws -> Geometry {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sourceType = CGImageSourceGetType(source),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int
        else { throw ImageAdjustmentRenderError.unreadable }

        guard CGImageSourceGetCount(source) == 1 else { throw ImageAdjustmentRenderError.multipleImages }

        // Core Image reads CMYK and indexed sources as RGB, so ImageIO's own properties decide.
        guard ImageFileWriting.isRGBOrGray(colorModel: properties[kCGImagePropertyColorModel as String] as? String),
              properties[kCGImagePropertyIsIndexed as String] as? Bool != true
        else { throw ImageAdjustmentRenderError.unsupportedColorModel }

        let tag = properties[kCGImagePropertyOrientation as String] as? Int ?? 1
        let geometry = Geometry(orientation: orientation.applied(toFileOrientation: tag), width: width, height: height)

        let type = ImageFileWriting.fileType(for: sourceType as String)
        let bakesOrientation = geometry.orientation != 1 && !ImageFileWriting.writesOrientation(type)

        // Unoriented unless baked, so the auxiliary planes copied below stay aligned with it.
        let input = CIImage(cgImageSource: source, index: 0, options: bakesOrientation ? [.applyOrientationProperty: true] : nil)

        guard let colorSpace = input.colorSpace,
              let format = ImageFileWriting.fileFormat(
                  model: colorSpace.model,
                  sixteenBit: (properties[kCGImagePropertyDepth as String] as? Int ?? 8) > 8,
                  alpha: properties[kCGImagePropertyHasAlpha as String] as? Bool ?? false
              )
        else { throw ImageAdjustmentRenderError.unsupportedColorModel }

        stage?(.rendering)

        // Baked, the input is the upright decode the crop is drawn on; otherwise the crop is mapped to the stored pixels.
        let stored = bakesOrientation ? crop : crop.unoriented(fileOrientation: tag)
        let kept = stored.apply(to: input)
        let written = Self.writtenSize(
            kept: stored.keptPixelSize(imageWidth: Int(input.extent.width), imageHeight: Int(input.extent.height)),
            turnedBy: bakesOrientation ? orientation : .up
        )

        let rendered = bakesOrientation
            ? orientation.apply(to: Self.apply(adjustments, to: kept).cropped(to: kept.extent))
            : Self.apply(adjustments, to: kept)

        guard let image = context.createCGImage(
            rendered,
            from: bakesOrientation ? rendered.extent : kept.extent,
            format: format,
            colorSpace: colorSpace,
            deferred: false
        ) else { throw ImageAdjustmentRenderError.renderFailed }

        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, type as CFString, 1, nil) else {
            throw ImageAdjustmentRenderError.unwritableType(type)
        }

        // The orientation key is undocumented for this call; without it HEIC is written as 1.
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyOrientation: bakesOrientation ? 1 : geometry.orientation,
        ]

        let fileTag = OrientationEdit(rawValue: tag) ?? .up

        if bakesOrientation {
            let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil).flatMap { CGImageMetadataCreateMutableCopy($0) }

            if let metadata {
                CGImageMetadataSetValueMatchingImageProperty(
                    metadata, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, 1 as CFNumber
                )
                Self.fitMetadata(
                    metadata, storedWidth: width, storedHeight: height, before: fileTag, crop: crop, after: orientation, written: written
                )
            }

            CGImageDestinationAddImageAndMetadata(output, image, metadata, options as CFDictionary)

            // Depth and mattes are left out: they would no longer line up with the turned pixels.
            ImageFormatConverter.addGainMaps(from: source, index: 0, before: fileTag, crop: crop, orientation: orientation, to: output)
        } else if !stored.isIdentity {
            let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil).flatMap { CGImageMetadataCreateMutableCopy($0) }

            if let metadata {
                Self.fitMetadata(metadata, storedWidth: width, storedHeight: height, before: .up, crop: stored, after: .up, written: written)
            }

            CGImageDestinationAddImageAndMetadata(output, image, metadata, options as CFDictionary)
            ImageFormatConverter.addGainMaps(from: source, index: 0, crop: stored, orientation: .up, to: output)
        } else {
            CGImageDestinationAddImageAndMetadata(output, image, CGImageSourceCopyMetadataAtIndex(source, 0, nil), options as CFDictionary)

            for auxiliaryType in ImageFormatConverter.carriedAuxiliaryTypes(cropped: false) {
                guard let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, auxiliaryType) else { continue }
                CGImageDestinationAddAuxiliaryDataInfo(output, auxiliaryType, info)
            }
        }

        stage?(.encoding)

        guard CGImageDestinationFinalize(output) else { throw ImageAdjustmentRenderError.encodeFailed }

        return Geometry(orientation: bakesOrientation ? 1 : geometry.orientation, width: written.width, height: written.height)
    }

    /// The written size: the kept size, swapped when `orientation` turns it a quarter.
    private static func writtenSize(kept: (width: Int, height: Int), turnedBy orientation: OrientationEdit) -> ImageFormatConverter.PixelSize {
        orientation.swapsDimensions
            ? ImageFormatConverter.PixelSize(width: kept.height, height: kept.width)
            : ImageFormatConverter.PixelSize(width: kept.width, height: kept.height)
    }

    /// The written size in EXIF when cropped, and the face regions moved with the pixels.
    private static func fitMetadata(
        _ metadata: CGMutableImageMetadata,
        storedWidth: Int,
        storedHeight: Int,
        before: OrientationEdit,
        crop: CropEdit,
        after: OrientationEdit,
        written: ImageFormatConverter.PixelSize
    ) {
        if !crop.isIdentity {
            ImageFormatConverter.setPixelDimensions(metadata, width: written.width, height: written.height)
        }

        ImageFormatConverter.remapRegions(
            metadata, storedWidth: storedWidth, storedHeight: storedHeight, before: before, crop: crop, after: after,
            writtenWidth: written.width, writtenHeight: written.height
        )
    }
}
