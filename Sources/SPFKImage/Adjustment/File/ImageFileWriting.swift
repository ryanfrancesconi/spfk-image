// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What an adjusted render, a format conversion and an orientation rewrite share in writing a file.
enum ImageFileWriting {
    /// Whether ImageIO's `colorModel` property names RGB or gray. A source reporting none counts as RGB.
    /// Core Image reads CMYK as RGB, so this property decides rather than the decoded color space.
    static func isRGBOrGray(colorModel: String?) -> Bool {
        guard let colorModel else { return true }
        return colorModel == kCGImagePropertyColorModelRGB as String || colorModel == kCGImagePropertyColorModelGray as String
    }

    /// Throws ``ImageAdjustmentRenderError/readBackMismatch`` unless the file at `url` reads back with
    /// `orientation` and `width` × `height` stored pixels.
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
