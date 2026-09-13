// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import SPFKBase
import UniformTypeIdentifiers

extension CGImage {
    /// Supports .png, .jpeg, .heif, and .tiff
    public func export(utType: UTType, to url: URL) throws {
        let ciContext = CIContext()
        let ciImage = CIImage(cgImage: self)

        guard let colorSpace = ciImage.colorSpace else {
            throw NSError(description: "Invalid colorSpace in returned CIImage")
        }

        switch utType {
        case .png:
            try ciContext.writePNGRepresentation(of: ciImage, to: url, format: .RGBA8, colorSpace: colorSpace)

        case .jpeg:
            try ciContext.writeJPEGRepresentation(of: ciImage, to: url, colorSpace: colorSpace)

        case .heif:
            try ciContext.writeHEIFRepresentation(of: ciImage, to: url, format: .RGBA8, colorSpace: colorSpace)

        case .tiff:
            try ciContext.writeTIFFRepresentation(of: ciImage, to: url, format: .RGBA8, colorSpace: colorSpace)

        default:
            throw NSError(file: #file, function: #function, description: "Unsupported UTType \(utType)")
        }
    }
}

extension CGImage {
    public var jpegRepresentation: Data? {
        try? dataRepresentation(utType: .jpeg)
    }

    public var pngRepresentation: Data? {
        try? dataRepresentation(utType: .png)
    }

    /// Generate data for the image in the format defined by utType.
    /// - Parameters:
    ///   - utType: The UTType for the image to generate
    ///   - dpi: The image's dpi
    ///   - compression: The compression level to apply (0...1)
    ///   - excludeGPSData: If true, strips any GPS information from the output
    ///   - otherOptions: Other options as defined in [documentation](https://developer.apple.com/documentation/imageio/cgimagedestination)
    /// - Returns: image data
    public func dataRepresentation(
        utType: UTType,
        dpi: CGFloat = 72,
        compression: CGFloat? = nil,
        excludeGPSData: Bool = true,
        otherOptions: [String: Any]? = nil
    ) throws -> Data {
        // Make sure that the DPI level is at least somewhat sane
        guard dpi >= 0 else {
            throw NSError(description: "invalid DPI \(dpi)")
        }

        var options: [CFString: Any] = [
            kCGImagePropertyPixelWidth: width,
            kCGImagePropertyPixelHeight: height,
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]

        if utType == .jpeg, let compression {
            options[kCGImageDestinationLossyCompressionQuality] = compression.clamped(to: 0 ... 1)
        }

        if excludeGPSData == true {
            options[kCGImageMetadataShouldExcludeGPS] = true
        }

        // Add in the user's customizations
        otherOptions?.forEach {
            options[$0.0 as CFString] = $0.1
        }

        let uniformTypeIdentifier = utType.identifier as CFString

        guard
            let mutableData = CFDataCreateMutable(nil, 0),
            let destination = CGImageDestinationCreateWithData(mutableData, uniformTypeIdentifier, 1, nil)
        else {
            throw NSError(description: "CGImageDestinationCreateWithData")
        }

        CGImageDestinationAddImage(destination, self, options as CFDictionary)

        // [Internal] Thread running at User-initiated quality-of-service class waiting on a thread without a QoS class specified (base priority 0). Investigate ways to avoid priority inversions

        CGImageDestinationFinalize(destination)

        let resultData = mutableData as Data

        if resultData.count == 0 {
            throw NSError(description: "resultData.count == 0")
        }

        return resultData
    }
}
