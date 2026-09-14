// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import SPFKTesting
import UniformTypeIdentifiers

/// Files for ``ImageAdjustmentFileRenderTests``, generated into a directory the caller owns. Nothing here
/// is bundled: a property a test relies on is written by the generator and asserted before use.
enum AdjustmentFileFixtures {
    struct GenerationError: Error {
        let message: String
    }

    static let captureDate = "2024:05:17 14:32:10"
    static let latitude = 37.7749
    static let keywords = ["alpha", "beta"]

    static func songbird() throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(TestBundleResources.shared.songbird as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw GenerationError(message: "songbird did not decode") }

        return image
    }

    /// `songbird.jpg` as `type`, tagged with `orientation`, a capture date, a GPS latitude and `dc:subject`.
    static func tagged(_ type: UTType, orientation: Int, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("tagged-\(orientation)").appendingPathExtension(for: type)
        let metadata = CGImageMetadataCreateMutable()

        guard CGImageMetadataSetValueMatchingImageProperty(
            metadata, kCGImagePropertyExifDictionary, kCGImagePropertyExifDateTimeOriginal, captureDate as CFString
        ),
            CGImageMetadataSetValueMatchingImageProperty(
                metadata, kCGImagePropertyGPSDictionary, kCGImagePropertyGPSLatitude, latitude as CFNumber
            ),
            CGImageMetadataSetValueMatchingImageProperty(
                metadata, kCGImagePropertyGPSDictionary, kCGImagePropertyGPSLatitudeRef, "N" as CFString
            ),
            let subject = CGImageMetadataTagCreate(
                kCGImageMetadataNamespaceDublinCore, kCGImageMetadataPrefixDublinCore, "subject" as CFString,
                .arrayUnordered, keywords as CFArray
            ),
            CGImageMetadataSetTagWithPath(metadata, nil, "dc:subject" as CFString, subject)
        else { throw GenerationError(message: "metadata could not be built") }

        try encode(
            try songbird(), to: url, type: type, metadata: metadata,
            options: [kCGImagePropertyOrientation: orientation]
        )

        return url
    }

    /// `songbird.jpg` as `type` with a synthetic Apple HDR gain map.
    static func gainMapped(_ type: UTType, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("gain-map").appendingPathExtension(for: type)
        let base = CIImage(cgImage: try songbird())
        let size = CGSize(width: base.extent.width / 2, height: base.extent.height / 2)

        let gradient = CIFilter.radialGradient()
        gradient.center = CGPoint(x: size.width / 2, y: size.height / 2)
        gradient.radius0 = 0
        gradient.radius1 = Float(min(size.width, size.height) / 2)
        gradient.color0 = CIColor.white
        gradient.color1 = CIColor.black

        guard let gainMap = gradient.outputImage?.cropped(to: CGRect(origin: .zero, size: size)),
              let space = CGColorSpace(name: CGColorSpace.displayP3)
        else { throw GenerationError(message: "gain map image could not be built") }

        let context = CIContext()
        let options: [CIImageRepresentationOption: Any] = [.hdrGainMapImage: gainMap]
        let data = type == .heic
            ? context.heifRepresentation(of: base, format: .RGBA8, colorSpace: space, options: options)
            : context.jpegRepresentation(of: base, colorSpace: space, options: options)

        guard let data else { throw GenerationError(message: "no \(type.identifier) representation") }
        try data.write(to: url)

        return url
    }

    /// A PNG whose left half is opaque and right half fully transparent.
    static func halfTransparentPNG(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("transparent.png")

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw GenerationError(message: "no RGBA context") }

        context.clear(CGRect(x: 0, y: 0, width: 64, height: 48))
        context.setFillColor(CGColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 48))

        guard let image = context.makeImage() else { throw GenerationError(message: "no image") }
        try encode(image, to: url, type: .png, metadata: nil)

        return url
    }

    /// A flat mid-gray grayscale JPEG.
    static func grayJPEG(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("gray.jpg")

        guard let space = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
              let context = CGContext(
                  data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else { throw GenerationError(message: "no gray context") }

        context.setFillColor(gray: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))

        guard let image = context.makeImage() else { throw GenerationError(message: "no image") }
        try encode(image, to: url, type: .jpeg, metadata: nil)

        return url
    }

    /// A TIFF holding two pages.
    static func twoPageTIFF(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("pages.tiff")
        let image = try songbird()

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 2, nil) else {
            throw GenerationError(message: "no TIFF destination")
        }

        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else { throw GenerationError(message: "TIFF did not encode") }

        return url
    }

    private static func encode(
        _ image: CGImage,
        to url: URL,
        type: UTType,
        metadata: CGImageMetadata?,
        options: [CFString: Any] = [:]
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw GenerationError(message: "no \(type.identifier) destination")
        }

        CGImageDestinationAddImageAndMetadata(destination, image, metadata, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { throw GenerationError(message: "\(type.identifier) did not encode") }
    }
}
