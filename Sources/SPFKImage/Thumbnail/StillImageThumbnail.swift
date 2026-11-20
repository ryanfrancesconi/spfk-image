// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreGraphics
import Foundation
import ImageIO
import SPFKBase

/// Downscaled decodes of still images: ImageIO for raster formats, `SVGImage` for SVG and
/// PDF-compatible Illustrator files.
///
/// Security-scoped access is the caller's.
public enum StillImageThumbnail {
    /// Decodes `url` with its long edge at most `maxPixelSize`, orientation applied.
    ///
    /// - Parameter allowsEmbeddedThumbnail: lets ImageIO answer from a thumbnail stored in the
    ///   file, which it returns at its own size whatever `maxPixelSize` asks for.
    public static func make(url: URL, maxPixelSize: Int, allowsEmbeddedThumbnail: Bool) -> CGImage? {
        #if os(macOS)
            if rendersThroughNSImage(url) {
                return SVGImage.render(url: url, maxPixelSize: maxPixelSize)
            }
        #endif

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(of: source, maxPixelSize: maxPixelSize, allowsEmbeddedThumbnail: allowsEmbeddedThumbnail)
    }

    /// ``make(url:maxPixelSize:allowsEmbeddedThumbnail:)`` for async code.
    ///
    /// A RAW decode blocks its thread on work needing a cooperative thread, so it runs under a
    /// ``BlockingCallLimiter/shared`` slot; anything else decodes inline. Never call it from the main actor.
    public static func admitted(url: URL, maxPixelSize: Int, allowsEmbeddedThumbnail: Bool) async -> CGImage? {
        #if os(macOS)
            if rendersThroughNSImage(url) {
                return SVGImage.render(url: url, maxPixelSize: maxPixelSize)
            }
        #endif

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        guard RAWDevelop.isRAW(source) else {
            return autoreleasepool {
                thumbnail(of: source, maxPixelSize: maxPixelSize, allowsEmbeddedThumbnail: allowsEmbeddedThumbnail)
            }
        }

        return await BlockingCallLimiter.shared.run {
            autoreleasepool {
                thumbnail(of: source, maxPixelSize: maxPixelSize, allowsEmbeddedThumbnail: allowsEmbeddedThumbnail)
            }
        }
    }

    private static func thumbnail(of source: CGImageSource, maxPixelSize: Int, allowsEmbeddedThumbnail: Bool) -> CGImage? {
        let sourceOption = allowsEmbeddedThumbnail
            ? kCGImageSourceCreateThumbnailFromImageIfAbsent
            : kCGImageSourceCreateThumbnailFromImageAlways

        let options: [CFString: Any] = [
            sourceOption: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The stored pixel dimensions, before orientation; for a vector file, the document's size in
    /// its own units. `nil` when they cannot be read.
    public static func sourceSize(of url: URL) -> CGSize? {
        #if os(macOS)
            if rendersThroughNSImage(url) {
                return SVGImage.intrinsicSize(of: url)
            }
        #endif

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat
        else { return nil }

        return CGSize(width: width, height: height)
    }

    /// Whether `url` renders sharply at any size, so a decode need not stop at its source size.
    public static func isResolutionIndependent(_ url: URL) -> Bool {
        #if os(macOS)
            rendersThroughNSImage(url)
        #else
            false
        #endif
    }

    #if os(macOS)
        private static func rendersThroughNSImage(_ url: URL) -> Bool {
            SVGImage.isSVG(url) || IllustratorImage.isPDFCompatible(url)
        }
    #endif
}
