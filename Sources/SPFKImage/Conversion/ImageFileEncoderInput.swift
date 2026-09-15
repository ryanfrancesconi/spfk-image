// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Accelerate
import CoreGraphics
import Foundation

/// One image for an ``ImageFileEncoder``: upright, at its output size, with the metadata the conversion keeps.
public struct ImageFileEncoderInput {
    public let image: CGImage

    /// Encode quality from 0 to 1.
    public let quality: Double

    /// The TIFF structure a JPEG's Exif segment holds, stating orientation 1 and the image's size. `nil` when the
    /// conversion keeps no EXIF.
    public let exif: Data?

    /// A serialized XMP packet. `nil` when the conversion keeps no metadata.
    public let xmp: Data?

    public init(image: CGImage, quality: Double, exif: Data?, xmp: Data?) {
        self.image = image
        self.quality = min(1, max(0, quality.isFinite ? quality : ImageAdjustmentRenderer.defaultFileQuality))
        self.exif = exif
        self.xmp = xmp
    }

    /// The image drawn as unpremultiplied RGBA at 8 or 16 bits per component.
    ///
    /// Samples stay in the image's own color space when it is RGB with a profile and standard range; any other
    /// space is converted to sRGB.
    public func rgbaPixels(bitsPerComponent: Int) throws -> RGBAPixelBuffer {
        guard bitsPerComponent == 8 || bitsPerComponent == 16 else { throw ImageConversionError.renderFailed }

        let width = image.width
        let height = image.height
        let rowBytes = width * 4 * (bitsPerComponent / 8)

        let imageSpace = image.colorSpace.flatMap {
            $0.model == .rgb && !CGColorSpaceUsesExtendedRange($0) && $0.copyICCData() != nil ? $0 : nil
        }

        guard let space = imageSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let iccProfile = space.copyICCData() as Data?
        else { throw ImageConversionError.renderFailed }

        let hasAlpha = ![CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        var bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        if bitsPerComponent == 16 {
            bitmapInfo |= CGImageByteOrderInfo.order16Little.rawValue
        }

        var data = Data(count: rowBytes * height)

        let drawn = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: rowBytes,
                space: space,
                bitmapInfo: bitmapInfo
            ) else { return false }

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            guard hasAlpha else { return true }

            var source = vImage_Buffer(
                data: bytes.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: rowBytes
            )
            var destination = source

            let error = bitsPerComponent == 8
                ? vImageUnpremultiplyData_RGBA8888(&source, &destination, vImage_Flags(kvImageNoFlags))
                : vImageUnpremultiplyData_RGBA16U(&source, &destination, vImage_Flags(kvImageNoFlags))

            return error == kvImageNoError
        }

        guard drawn else { throw ImageConversionError.renderFailed }

        return RGBAPixelBuffer(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            hasAlpha: hasAlpha,
            iccProfile: iccProfile
        )
    }
}
