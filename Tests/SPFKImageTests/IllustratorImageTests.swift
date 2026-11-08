// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)
    import AppKit
    import Foundation
    import Testing

    @testable import SPFKImage

    final class IllustratorImageTests {
        private let directory: URL

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("spfk-image-ai-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        /// A one-page PDF, which is what a PDF-compatible Illustrator file is to `NSImage`: a 40 x 20
        /// point page, red left half, blue right half.
        private func pdfCompatible(name: String = "two-tone.ai") throws -> URL {
            let url = directory.appendingPathComponent(name)
            var mediaBox = CGRect(x: 0, y: 0, width: 40, height: 20)
            let context = try #require(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
            context.beginPDFPage(nil)
            context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
            context.fill(CGRect(x: 20, y: 0, width: 20, height: 20))
            context.endPDFPage()
            context.closePDF()
            return url
        }

        /// The header of an Illustrator 8 file, which is PostScript.
        private func postScriptEra() throws -> URL {
            let url = directory.appendingPathComponent("legacy.ai")
            try Data("%!PS-Adobe-3.0\n%%Creator: Adobe Illustrator(R) 8.0\n%%BoundingBox: 0 0 40 20\n%%EOF\n".utf8).write(to: url)
            return url
        }

        private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
            guard let data = image.dataProvider?.data as Data? else { return [] }
            let offset = y * image.bytesPerRow + x * 4
            return Array(data[offset ..< offset + 4])
        }

        @Test func onlyAnIllustratorFileHoldingAPDFIsPDFCompatible() throws {
            let pdf = try pdfCompatible()
            #expect(IllustratorImage.isPDFCompatible(pdf))
            #expect(IllustratorImage.isPDFCompatible(try pdfCompatible(name: "upper.AI")))
            #expect(IllustratorImage.isPDFCompatible(try postScriptEra()) == false)

            let renamed = directory.appendingPathComponent("page.pdf")
            try FileManager.default.copyItem(at: pdf, to: renamed)
            #expect(IllustratorImage.isPDFCompatible(renamed) == false)

            #expect(IllustratorImage.isPDFCompatible(directory.appendingPathComponent("missing.ai")) == false)
        }

        @Test func aPDFCompatibleFileRendersAtTheAskedLongEdge() throws {
            let url = try pdfCompatible()

            #expect(StillImageThumbnail.isResolutionIndependent(url))
            #expect(StillImageThumbnail.sourceSize(of: url) == CGSize(width: 40, height: 20))

            let image = try #require(StillImageThumbnail.make(url: url, maxPixelSize: 400, allowsEmbeddedThumbnail: true))
            #expect(image.width == 400)
            #expect(image.height == 200)
            #expect(pixel(image, x: 100, y: 100) == [255, 0, 0, 255])
            #expect(pixel(image, x: 300, y: 100) == [0, 0, 255, 255])
        }

        @Test func aPostScriptEraFileIsNil() throws {
            let url = try postScriptEra()

            #expect(StillImageThumbnail.isResolutionIndependent(url) == false)
            #expect(StillImageThumbnail.sourceSize(of: url) == nil)
            #expect(StillImageThumbnail.make(url: url, maxPixelSize: 128, allowsEmbeddedThumbnail: true) == nil)
        }
    }
#endif
