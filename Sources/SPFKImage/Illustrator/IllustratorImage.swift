// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

#if os(macOS)
    import Foundation
    import UniformTypeIdentifiers

    /// Illustrator files, which `NSImage` reads only when they were saved PDF-compatible.
    public enum IllustratorImage {
        private static let type = UTType("com.adobe.illustrator.ai-image")

        /// Whether `url` is an Illustrator file whose content is a PDF, so `SVGImage` can render it.
        /// Opens the file for any Illustrator extension; answers from the extension otherwise.
        public static func isPDFCompatible(_ url: URL) -> Bool {
            guard let type,
                  UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: type) == true,
                  let handle = try? FileHandle(forReadingFrom: url)
            else { return false }

            defer { try? handle.close() }

            return (try? handle.read(upToCount: 4)) == Data("%PDF".utf8)
        }
    }
#endif
