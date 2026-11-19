// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import SPFKBase
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

    /// The SDK declares no constant for AVIF.
    static let avif = UTType(importedAs: "public.avif")

    static func songbird() throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(TestBundleResources.shared.songbird as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw GenerationError(message: "songbird did not decode") }

        return image
    }

    /// `songbird.jpg` as `type`, tagged with `orientation`, a capture date, a GPS latitude and `dc:subject`.
    /// An AVIF or HEIC encode can block its thread, so the generator runs in a `BlockingCallLimiter` slot.
    static func tagged(_ type: UTType, orientation: Int, in directory: URL) async throws -> URL {
        try await BlockingCallLimiter.shared.run { try makeTagged(type, orientation: orientation, in: directory) }
    }

    private static func makeTagged(_ type: UTType, orientation: Int, in directory: URL) throws -> URL {
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

    /// Which gain map a fixture carries. Core Image writes only ISO 21496-1 maps, so an Apple map is the ISO map's
    /// data written through ImageIO under Apple's type: enough to prove a map is carried, not that Apple's HDR
    /// metadata is read.
    enum GainMapFormat: String, CaseIterable, Sendable {
        case apple
        case iso

        @available(macOS 15, iOS 18, *)
        var auxiliaryType: CFString {
            switch self {
            case .apple: kCGImageAuxiliaryDataTypeHDRGainMap
            case .iso: kCGImageAuxiliaryDataTypeISOGainMap
            }
        }

        /// The map `url` carries in this format, if any.
        @available(macOS 15, iOS 18, *)
        func info(_ url: URL) -> [String: Any]? {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, auxiliaryType) as? [String: Any]
        }
    }

    /// `songbird.jpg` as `type` with a gain map in `format`.
    @available(macOS 15, iOS 18, *)
    static func gainMapped(_ type: UTType, format: GainMapFormat, in directory: URL) async throws -> URL {
        try await BlockingCallLimiter.shared.run { try makeGainMapped(type, format: format, in: directory) }
    }

    /// ``gainMapped(_:format:in:)`` for a caller already holding a slot.
    @available(macOS 15, iOS 18, *)
    static func makeGainMapped(_ type: UTType, format: GainMapFormat, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("gain-map-\(format.rawValue)").appendingPathExtension(for: type)
        try writeGainMapped(CIImage(cgImage: try songbird()), type: type, format: format, to: url)
        return url
    }

    /// `base` as `type`, with a gain map Core Image computes from a brighter copy of it. Core Image has no AVIF
    /// representation, so an AVIF, like an Apple map, is the HEIC's image, metadata and map copied through ImageIO.
    @available(macOS 15, iOS 18, *)
    static func writeGainMapped(_ base: CIImage, type: UTType, format: GainMapFormat, to url: URL) throws {
        guard let space = CGColorSpace(name: CGColorSpace.displayP3) else { throw GenerationError(message: "no Display P3") }

        let encoded: UTType = type == avif ? .heic : type
        let hdr = base.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 1.5])
        let options: [CIImageRepresentationOption: Any] = [.hdrImage: hdr]
        let context = CIContext()

        let data = encoded == .heic
            ? context.heifRepresentation(of: base, format: .RGBA8, colorSpace: space, options: options)
            : context.jpegRepresentation(of: base, colorSpace: space, options: options)

        guard let data else { throw GenerationError(message: "no \(encoded.identifier) representation") }

        if type == encoded, format == .iso {
            try data.write(to: url)
            return
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let gainMap = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw GenerationError(message: "no gain-mapped \(type.identifier)") }

        CGImageDestinationAddImageAndMetadata(destination, image, CGImageSourceCopyMetadataAtIndex(source, 0, nil), nil)
        CGImageDestinationAddAuxiliaryDataInfo(destination, format.auxiliaryType, gainMap)

        guard CGImageDestinationFinalize(destination) else { throw GenerationError(message: "\(type.identifier) did not encode") }
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

    /// A flat CMYK TIFF.
    static func cmykTIFF(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("cmyk.tiff")

        guard let space = CGColorSpace(name: CGColorSpace.genericCMYK),
              let context = CGContext(
                  data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else { throw GenerationError(message: "no CMYK context") }

        context.setFillColor(CGColor(genericCMYKCyan: 0.2, magenta: 0.4, yellow: 0.6, black: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))

        guard let image = context.makeImage() else { throw GenerationError(message: "no image") }
        try encode(image, to: url, type: .tiff, metadata: nil)

        return url
    }

    /// A flat two-color indexed PNG.
    static func indexedPNG(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("indexed.png")
        var palette: [UInt8] = [255, 0, 0, 0, 0, 255]

        guard let base = CGColorSpace(name: CGColorSpace.sRGB),
              let space = CGColorSpace(indexedBaseSpace: base, last: 1, colorTable: &palette),
              let provider = CGDataProvider(data: Data(repeating: 1, count: 64 * 48) as CFData),
              let image = CGImage(
                  width: 64, height: 48, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 64, space: space,
                  bitmapInfo: [], provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              )
        else { throw GenerationError(message: "no indexed image") }

        try encode(image, to: url, type: .png, metadata: nil)

        return url
    }

    /// A flat 16-bit-per-channel RGB file of `type`.
    static func sixteenBit(_ type: UTType, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("sixteen-bit").appendingPathExtension(for: type)

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: 64, height: 48, bitsPerComponent: 16, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { throw GenerationError(message: "no 16-bit context") }

        context.setFillColor(CGColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))

        guard let image = context.makeImage() else { throw GenerationError(message: "no image") }
        try encode(image, to: url, type: type, metadata: nil)

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
