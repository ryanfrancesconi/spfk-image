// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension ImageAdjustmentRenderer {
    /// JPEG and HEIC encode quality for a rendered file.
    public static let defaultFileQuality: Double = 0.9

    /// Renders `adjustments` into a new file at `destination`, in the source's own format.
    ///
    /// Adjusts the source's unoriented pixels and writes them with its metadata, its orientation tag and
    /// every auxiliary image (gain maps, depth, mattes) carried unchanged. `destination` must not exist,
    /// and exists afterwards only if this returns; `source` is never written.
    public func renderFile(
        _ adjustments: ImageAdjustmentDescription,
        source: URL,
        destination: URL,
        quality: Double = defaultFileQuality
    ) throws {
        try renderFile(adjustments, source: source, destination: destination, quality: quality, expectedOrientation: nil)
    }

    /// `expectedOrientation` replaces the orientation the read-back requires, so a test can force a mismatch.
    func renderFile(
        _ adjustments: ImageAdjustmentDescription,
        source: URL,
        destination: URL,
        quality: Double,
        expectedOrientation: Int?
    ) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ImageAdjustmentRenderError.destinationExists
        }

        do {
            let written = try autoreleasepool {
                try write(adjustments, source: source, destination: destination, quality: quality)
            }

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
        source url: URL,
        destination: URL,
        quality: Double
    ) throws -> Geometry {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sourceType = CGImageSourceGetType(source),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int
        else { throw ImageAdjustmentRenderError.unreadable }

        guard CGImageSourceGetCount(source) == 1 else { throw ImageAdjustmentRenderError.multipleImages }

        let geometry = Geometry(
            orientation: properties[kCGImagePropertyOrientation as String] as? Int ?? 1,
            width: width,
            height: height
        )

        // Unoriented, so the auxiliary planes copied below stay aligned with it.
        let input = CIImage(cgImageSource: source, index: 0, options: nil)

        guard let colorSpace = input.colorSpace,
              let format = Self.fileFormat(
                  model: colorSpace.model,
                  sixteenBit: (properties[kCGImagePropertyDepth as String] as? Int ?? 8) > 8,
                  alpha: properties[kCGImagePropertyHasAlpha as String] as? Bool ?? false
              )
        else { throw ImageAdjustmentRenderError.unsupportedColorModel }

        guard let image = context.createCGImage(
            Self.apply(adjustments, to: input),
            from: input.extent,
            format: format,
            colorSpace: colorSpace,
            deferred: false
        ) else { throw ImageAdjustmentRenderError.renderFailed }

        let type = Self.fileType(for: sourceType as String)

        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, type as CFString, 1, nil) else {
            throw ImageAdjustmentRenderError.unwritableType(type)
        }

        // The orientation key is undocumented for this call; without it HEIC is written as 1.
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyOrientation: geometry.orientation,
        ]

        CGImageDestinationAddImageAndMetadata(output, image, CGImageSourceCopyMetadataAtIndex(source, 0, nil), options as CFDictionary)

        for auxiliaryType in Self.auxiliaryDataTypes {
            guard let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, auxiliaryType) else { continue }
            CGImageDestinationAddAuxiliaryDataInfo(output, auxiliaryType, info)
        }

        guard CGImageDestinationFinalize(output) else { throw ImageAdjustmentRenderError.encodeFailed }

        return geometry
    }

    private static func verify(_ url: URL, orientation: Int, width: Int, height: Int) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              properties[kCGImagePropertyOrientation as String] as? Int ?? 1 == orientation,
              properties[kCGImagePropertyPixelWidth as String] as? Int == width,
              properties[kCGImagePropertyPixelHeight as String] as? Int == height
        else { throw ImageAdjustmentRenderError.readBackMismatch }
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
