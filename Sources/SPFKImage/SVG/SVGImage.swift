// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

#if os(macOS)
    import AppKit
    import UniformTypeIdentifiers

    /// Rasterizes SVG files, which ImageIO cannot read, through `NSImage`.
    ///
    /// Filtered elements and `<foreignObject>` are not drawn, and gzip-compressed `.svgz` is not
    /// read at all.
    public enum SVGImage {
        /// Whether `url` names an SVG this type can read. `.svgz` resolves to the same type but
        /// `NSImage` cannot open it, so it is excluded.
        public static func isSVG(_ url: URL) -> Bool {
            let pathExtension = url.pathExtension.lowercased()

            guard pathExtension != "svgz",
                  let type = UTType(filenameExtension: pathExtension)
            else { return false }

            return type.conforms(to: .svg)
        }

        /// The document's size in SVG user units, or `nil` when it cannot be read or has no
        /// extent.
        public static func intrinsicSize(of url: URL) -> CGSize? {
            autoreleasepool {
                guard let image = NSImage(contentsOf: url) else { return nil }
                return size(of: image)
            }
        }

        /// Renders `url` aspect-fit so its long edge is `maxPixelSize`, on a transparent sRGB
        /// background. Safe to call concurrently.
        public static func render(url: URL, maxPixelSize: Int) -> CGImage? {
            guard maxPixelSize > 0 else { return nil }

            return autoreleasepool {
                guard let image = NSImage(contentsOf: url),
                      let size = size(of: image),
                      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
                else { return nil }

                let scale = CGFloat(maxPixelSize) / max(size.width, size.height)
                let width = max(1, Int((size.width * scale).rounded()))
                let height = max(1, Int((size.height * scale).rounded()))

                guard let context = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return nil }

                // A context per call: `NSGraphicsContext.current` is per thread.
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
                NSGraphicsContext.restoreGraphicsState()

                return context.makeImage()
            }
        }

        private static func size(of image: NSImage) -> CGSize? {
            let size = image.size

            guard image.isValid,
                  size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0
            else { return nil }

            return size
        }
    }
#endif
