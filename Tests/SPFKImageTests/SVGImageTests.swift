// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS)
    import AppKit
    import Foundation
    import Testing

    @testable import SPFKImage

    final class SVGImageTests {
        private let directory: URL

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("spfk-image-svg-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        private func write(_ contents: String, name: String) throws -> URL {
            let url = directory.appendingPathComponent(name)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        /// A 40 x 20 document: red left half, blue right half.
        private func twoTone(name: String = "two-tone.svg") throws -> URL {
            try write(
                """
                <svg xmlns="http://www.w3.org/2000/svg" width="40" height="20" viewBox="0 0 40 20">
                <rect width="20" height="20" fill="#ff0000"/><rect x="20" width="20" height="20" fill="#0000ff"/>
                </svg>
                """,
                name: name
            )
        }

        /// The RGBA bytes at a top-left-origin position of a render, which is 8-bit RGBA.
        private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
            guard let data = Self.bytes(image) else { return [] }
            let offset = y * image.bytesPerRow + x * 4
            return Array(data[offset ..< offset + 4])
        }

        private static func bytes(_ image: CGImage) -> Data? {
            image.dataProvider?.data as Data?
        }

        // MARK: - Type

        @Test func svgzIsNotTreatedAsReadable() {
            #expect(SVGImage.isSVG(URL(fileURLWithPath: "/a/b.svg")))
            #expect(SVGImage.isSVG(URL(fileURLWithPath: "/a/b.SVG")))
            #expect(SVGImage.isSVG(URL(fileURLWithPath: "/a/b.svgz")) == false)
            #expect(SVGImage.isSVG(URL(fileURLWithPath: "/a/b.png")) == false)
        }

        // MARK: - Size

        @Test func intrinsicSizeIsTheDocumentSize() throws {
            #expect(SVGImage.intrinsicSize(of: try twoTone()) == CGSize(width: 40, height: 20))
        }

        @Test func aViewBoxAloneGivesTheSize() throws {
            let url = try write(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 30 10"><rect width="30" height="10"/></svg>"#, name: "viewbox.svg")
            #expect(SVGImage.intrinsicSize(of: url) == CGSize(width: 30, height: 10))
        }

        // MARK: - Render

        @Test func rendersToTheLongEdgeAtTheDocumentAspect() throws {
            let image = try #require(SVGImage.render(url: try twoTone(), maxPixelSize: 200))

            #expect(image.width == 200)
            #expect(image.height == 100)
            #expect(pixel(image, x: 50, y: 50) == [255, 0, 0, 255])
            #expect(pixel(image, x: 150, y: 50) == [0, 0, 255, 255])
        }

        @Test func uncoveredAreaIsTransparent() throws {
            let url = try write(#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="5" height="10"/></svg>"#, name: "half.svg")
            let image = try #require(SVGImage.render(url: url, maxPixelSize: 100))

            #expect(pixel(image, x: 75, y: 50).last == 0)
        }

        @Test func aNonSVGFileIsNil() throws {
            let url = try write("not an svg", name: "bogus.svg")

            #expect(SVGImage.render(url: url, maxPixelSize: 64) == nil)
            #expect(SVGImage.intrinsicSize(of: url) == nil)
        }

        /// An SVG font: valid SVG with no width, height, viewBox or drawable content.
        @Test func aDocumentWithNoExtentIsNil() throws {
            let url = try write(
                #"<svg xmlns="http://www.w3.org/2000/svg"><defs><font id="f" horiz-adv-x="512"><glyph unicode="a" d="M0 0h10v10z"/></font></defs></svg>"#,
                name: "font.svg"
            )

            #expect(SVGImage.render(url: url, maxPixelSize: 64) == nil)
            #expect(SVGImage.intrinsicSize(of: url) == nil)
        }

        @Test func concurrentRendersMatchSerialOnes() async throws {
            let urls = try (0 ..< 8).map { try twoTone(name: "tone-\($0).svg") }
            let serial = urls.map { SVGImage.render(url: $0, maxPixelSize: 96).flatMap(Self.bytes) }

            let concurrent = await withTaskGroup(of: (Int, Data?).self) { group in
                for _ in 0 ..< 8 {
                    for (index, url) in urls.enumerated() {
                        group.addTask { (index, SVGImage.render(url: url, maxPixelSize: 96).flatMap(Self.bytes)) }
                    }
                }
                var results: [(Int, Data?)] = []
                for await result in group { results.append(result) }
                return results
            }

            #expect(serial.allSatisfy { $0 != nil })
            #expect(concurrent.count == 64)
            for (index, data) in concurrent {
                #expect(data == serial[index])
            }
        }

        // MARK: - Still thumbnail

        @Test func theStillThumbnailRoutesSVGThroughTheRenderer() throws {
            let url = try twoTone()

            #expect(StillImageThumbnail.isResolutionIndependent(url))
            #expect(StillImageThumbnail.sourceSize(of: url) == CGSize(width: 40, height: 20))

            let image = try #require(StillImageThumbnail.make(url: url, maxPixelSize: 128, allowsEmbeddedThumbnail: true))
            #expect(image.width == 128)
            #expect(image.height == 64)
        }
    }
#endif
