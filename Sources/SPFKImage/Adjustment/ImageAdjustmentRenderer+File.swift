// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import ImageIO
import SPFKBase
import UniformTypeIdentifiers

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
    /// Adjusts the source's unoriented pixels and writes them with its metadata, its orientation tag with
    /// `orientation` performed, and every auxiliary image (gain maps, depth, mattes) carried unchanged.
    /// A format that cannot store an orientation (AVIF) is written upright, with orientation 1, and its gain maps
    /// turned to match. `destination` must not exist, and exists afterwards only if this returns; `source` is never
    /// written.
    /// `stage` is called as each stage begins, and not after a throw. Waits for a ``BlockingCallLimiter`` slot,
    /// since an AV1 encode blocks its thread.
    public func renderFile(
        _ adjustments: ImageAdjustmentDescription,
        orientation: OrientationEdit = .up,
        source: URL,
        destination: URL,
        quality: Double = defaultFileQuality,
        stage: (@Sendable (ImageRenderStage) -> Void)? = nil
    ) async throws {
        try await BlockingCallLimiter.shared.run {
            try Task.checkCancellation()

            try renderFile(
                adjustments, orientation: orientation, source: source, destination: destination, quality: quality,
                expectedOrientation: nil, stage: stage
            )
        }
    }

    /// `expectedOrientation` replaces the orientation the read-back requires, so a test can force a mismatch.
    func renderFile(
        _ adjustments: ImageAdjustmentDescription,
        orientation: OrientationEdit = .up,
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
                    adjustments, orientation: orientation, source: source, destination: destination, quality: quality,
                    stage: stage
                )
            }

            stage?(.verifying)

            try Self.verify(
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
        let colorModel = properties[kCGImagePropertyColorModel as String] as? String

        guard colorModel.map({ $0 == kCGImagePropertyColorModelRGB as String || $0 == kCGImagePropertyColorModelGray as String }) ?? true,
              properties[kCGImagePropertyIsIndexed as String] as? Bool != true
        else { throw ImageAdjustmentRenderError.unsupportedColorModel }

        let geometry = Geometry(
            orientation: orientation.applied(toFileOrientation: properties[kCGImagePropertyOrientation as String] as? Int ?? 1),
            width: width,
            height: height
        )

        let type = Self.fileType(for: sourceType as String)
        let bakesOrientation = geometry.orientation != 1 && !Self.writesOrientation(type)

        // Unoriented unless baked, so the auxiliary planes copied below stay aligned with it.
        let input = CIImage(cgImageSource: source, index: 0, options: bakesOrientation ? [.applyOrientationProperty: true] : nil)

        guard let colorSpace = input.colorSpace,
              let format = Self.fileFormat(
                  model: colorSpace.model,
                  sixteenBit: (properties[kCGImagePropertyDepth as String] as? Int ?? 8) > 8,
                  alpha: properties[kCGImagePropertyHasAlpha as String] as? Bool ?? false
              )
        else { throw ImageAdjustmentRenderError.unsupportedColorModel }

        stage?(.rendering)

        let rendered = bakesOrientation
            ? orientation.apply(to: Self.apply(adjustments, to: input).cropped(to: input.extent))
            : Self.apply(adjustments, to: input)

        guard let image = context.createCGImage(
            rendered,
            from: bakesOrientation ? rendered.extent : input.extent,
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

        if bakesOrientation {
            let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil).flatMap { CGImageMetadataCreateMutableCopy($0) }

            if let metadata {
                CGImageMetadataSetValueMatchingImageProperty(
                    metadata, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, 1 as CFNumber
                )
            }

            CGImageDestinationAddImageAndMetadata(output, image, metadata, options as CFDictionary)

            // Depth and mattes are left out: they would no longer line up with the turned pixels.
            ImageFormatConverter.addGainMaps(from: source, index: 0, orientation: geometry.orientation, to: output)
        } else {
            CGImageDestinationAddImageAndMetadata(output, image, CGImageSourceCopyMetadataAtIndex(source, 0, nil), options as CFDictionary)

            for auxiliaryType in Self.auxiliaryDataTypes {
                guard let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, auxiliaryType) else { continue }
                CGImageDestinationAddAuxiliaryDataInfo(output, auxiliaryType, info)
            }
        }

        stage?(.encoding)

        guard CGImageDestinationFinalize(output) else { throw ImageAdjustmentRenderError.encodeFailed }

        guard bakesOrientation else { return geometry }

        let displayed = ImageFormatConverter.displayedSize(width: width, height: height, orientation: geometry.orientation)
        return Geometry(orientation: 1, width: displayed.width, height: displayed.height)
    }

    static func verify(_ url: URL, orientation: Int, width: Int, height: Int) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              properties[kCGImagePropertyOrientation as String] as? Int ?? 1 == orientation,
              properties[kCGImagePropertyPixelWidth as String] as? Int == width,
              properties[kCGImagePropertyPixelHeight as String] as? Int == height
        else { throw ImageAdjustmentRenderError.readBackMismatch }
    }

    /// Whether ImageIO writes an orientation tag for `typeIdentifier`. It reads AVIF's and never writes one.
    static func writesOrientation(_ typeIdentifier: String) -> Bool {
        typeIdentifier != ImageFormatConverter.avifIdentifier
    }

    /// The source's own type, except `public.heif`, which ImageIO cannot create a destination for.
    static func fileType(for sourceType: String) -> String {
        sourceType == UTType.heif.identifier ? UTType.heic.identifier : sourceType
    }

    /// An 8- or 16-bit bitmap in the source's channel layout, with alpha only when it has alpha.
    static func fileFormat(model: CGColorSpaceModel, sixteenBit: Bool, alpha: Bool) -> CIFormat? {
        switch model {
        case .rgb: sixteenBit ? (alpha ? .RGBA16 : .RGBX16) : (alpha ? .RGBA8 : .RGBX8)
        case .monochrome: sixteenBit ? (alpha ? .LA16 : .L16) : (alpha ? .LA8 : .L8)
        default: nil
        }
    }

    static var auxiliaryDataTypes: [CFString] {
        var types: [CFString] = [
            kCGImageAuxiliaryDataTypeHDRGainMap,
            kCGImageAuxiliaryDataTypeDepth,
            kCGImageAuxiliaryDataTypeDisparity,
            kCGImageAuxiliaryDataTypePortraitEffectsMatte,
            kCGImageAuxiliaryDataTypeSemanticSegmentationSkinMatte,
            kCGImageAuxiliaryDataTypeSemanticSegmentationHairMatte,
            kCGImageAuxiliaryDataTypeSemanticSegmentationTeethMatte,
            kCGImageAuxiliaryDataTypeSemanticSegmentationGlassesMatte,
            kCGImageAuxiliaryDataTypeSemanticSegmentationSkyMatte,
        ]

        if #available(macOS 15, iOS 18, *) {
            types.append(kCGImageAuxiliaryDataTypeISOGainMap)
        }

        return types
    }
}
