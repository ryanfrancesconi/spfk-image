// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import ImageIO
import UniformTypeIdentifiers

extension ImageOrientationEdit {
    /// The types ``rewriteFile(source:destination:)`` can write. ImageIO refuses GIF, and has no
    /// destination for WebP, JPEG XL or DNG.
    public static let losslessRewriteTypes: Set<UTType> = [.jpeg, .heic, .png, .tiff]

    /// Copies `source` to `destination` with only its orientation tag changed, this edit performed on it.
    ///
    /// The encoded image, metadata and auxiliary images are copied as they are. `destination` must not
    /// exist, and exists afterwards only if this returns; `source` is never written.
    public func rewriteFile(source: URL, destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ImageAdjustmentRenderError.destinationExists
        }

        do {
            let geometry = try autoreleasepool { try copy(source: source, destination: destination) }

            try ImageAdjustmentRenderer.verify(
                destination, orientation: geometry.orientation, width: geometry.width, height: geometry.height
            )
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private func copy(source url: URL, destination: URL) throws -> (orientation: Int, width: Int, height: Int) {
        // From the bytes rather than the URL, so the type is the content's: a HEIC named `.heif` reads
        // as `public.heif` by URL, and ImageIO can neither create that type nor copy it into HEIC.
        let data = try Data(contentsOf: url, options: .mappedIfSafe)

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int
        else { throw ImageAdjustmentRenderError.unreadable }

        guard CGImageSourceGetCount(source) == 1 else { throw ImageAdjustmentRenderError.multipleImages }

        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, type, 1, nil) else {
            throw ImageAdjustmentRenderError.unwritableType(type as String)
        }

        let orientation = applied(toFileOrientation: properties[kCGImagePropertyOrientation as String] as? Int ?? 1)
        let options: [CFString: Any] = [kCGImageDestinationOrientation: orientation]

        guard CGImageDestinationCopyImageSource(output, source, options as CFDictionary, nil) else {
            throw ImageAdjustmentRenderError.encodeFailed
        }

        return (orientation, width, height)
    }
}
