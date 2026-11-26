// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import SPFKBase
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

/// The crop step: what it keeps, where it sits in the chain, and its straighten against Core Image's.
@Suite(.tags(.file))
final class ImageAdjustmentCropTests {
    private let renderer = ImageAdjustmentRenderer()
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spfk-image-crop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Fixtures

    private struct RGB: Equatable {
        var r: UInt8, g: UInt8, b: UInt8
    }

    private static let topLeft = RGB(r: 255, g: 0, b: 0)
    private static let topRight = RGB(r: 0, g: 255, b: 0)
    private static let bottomLeft = RGB(r: 0, g: 0, b: 255)
    private static let bottomRight = RGB(r: 255, g: 255, b: 255)
    private static let mark = RGB(r: 0, g: 0, b: 0)
    /// The mark's top-left pixel, from the image's top left; inside the top-left quadrant.
    private static let markOrigin = (x: 30, y: 12)

    /// 200 × 100 in four colored quadrants, with a 4-pixel black mark off center in the top-left one.
    private func quadrants(width: Int = 200, height: Int = 100) throws -> CGImage {
        try bitmap(width: width, height: height) { context in
            // Core Graphics is y up: the top half is at `height / 2`.
            let halfWidth = width / 2
            let halfHeight = height / 2
            let fills: [(RGB, CGRect)] = [
                (Self.topLeft, CGRect(x: 0, y: halfHeight, width: halfWidth, height: halfHeight)),
                (Self.topRight, CGRect(x: halfWidth, y: halfHeight, width: halfWidth, height: halfHeight)),
                (Self.bottomLeft, CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight)),
                (Self.bottomRight, CGRect(x: halfWidth, y: 0, width: halfWidth, height: halfHeight)),
                (Self.mark, CGRect(x: Self.markOrigin.x, y: height - Self.markOrigin.y - 4, width: 4, height: 4)),
            ]
            for (color, rect) in fills {
                context.setFillColor(red: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255, blue: CGFloat(color.b) / 255, alpha: 1)
                context.fill(rect)
            }
        }
    }

    private func flat(gray: CGFloat, width: Int, height: Int) throws -> CGImage {
        try bitmap(width: width, height: height) { context in
            context.setFillColor(red: gray, green: gray, blue: gray, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func bitmap(width: Int, height: Int, draw: (CGContext) -> Void) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        draw(context)
        return try #require(context.makeImage())
    }

    /// RGBA8 sRGB bytes, top row first.
    private func bytes(_ image: CGImage?) throws -> [UInt8] {
        let image = try #require(image)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)

        try data.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }

        return data
    }

    private func pixel(_ data: [UInt8], width: Int, x: Int, y: Int) -> RGB {
        let index = (y * width + x) * 4
        return RGB(r: data[index], g: data[index + 1], b: data[index + 2])
    }

    private func render(_ cropEdit: CropEdit, orientation: OrientationEdit = .up, adjustments: ImageAdjustmentDescription = .init(), source: CGImage) throws -> CGImage {
        try #require(renderer.render(adjustments, orientation: orientation, cropEdit: cropEdit, source: source))
    }

    // MARK: - What is kept

    @Test func aQuarterCropKeepsThatQuarterAtItsPixelSize() throws {
        let source = try quadrants()
        let crop = CropEdit(centerX: -0.25, centerY: -0.25, width: 0.5, height: 0.5)
        let output = try render(crop, source: source)
        let size = crop.pixelSize(imageWidth: source.width, imageHeight: source.height)

        #expect(output.width == size.width)
        #expect(output.height == size.height)

        let data = try bytes(output)
        #expect(pixel(data, width: output.width, x: 0, y: 0) == Self.topLeft)
        #expect(pixel(data, width: output.width, x: output.width - 1, y: output.height - 1) == Self.topLeft)
        #expect(pixel(data, width: output.width, x: Self.markOrigin.x + 1, y: Self.markOrigin.y + 1) == Self.mark)
    }

    @Test func anOffCenterCropKeepsTheMarkWhereItWas() throws {
        let source = try quadrants()
        // Kept: x 20…120, y 10…60 of the source.
        let crop = CropEdit(centerX: -0.15, centerY: -0.15, width: 0.5, height: 0.5)
        let output = try render(crop, source: source)
        let data = try bytes(output)

        #expect(pixel(data, width: output.width, x: Self.markOrigin.x - 20 + 1, y: Self.markOrigin.y - 10 + 1) == Self.mark)
        #expect(pixel(data, width: output.width, x: output.width - 1, y: 0) == Self.topRight)
    }

    @Test func anIdentityCropRendersBitIdenticalToNone() throws {
        let source = try CGImage.contentsOf(url: TestBundleResources.shared.songbird)
        let adjustments = ImageAdjustmentDescription(light: .init(exposure: 0.4), vignette: .init(amount: 0.5))

        let plain = try bytes(renderer.render(adjustments, orientation: .right, source: source))
        let identity = try bytes(renderer.render(adjustments, orientation: .right, cropEdit: CropEdit(aspect: .square), source: source))

        #expect(plain == identity)
    }

    /// SplitMix64, so the random crops below are the same every run.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Contained or not, on odd and even sizes, the render's size is the size rule's.
    @Test(arguments: [(200, 100), (201, 133), (97, 160)])
    func theKeptExtentIsTheKeptPixelSize(width: Int, height: Int) throws {
        let input = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        var generator = SeededGenerator(state: UInt64(width * 1000 + height))

        for _ in 0 ..< 40 {
            let crop = CropEdit(
                centerX: .random(in: -0.4 ... 0.4, using: &generator),
                centerY: .random(in: -0.4 ... 0.4, using: &generator),
                width: .random(in: 0.05 ... 1, using: &generator),
                height: .random(in: 0.05 ... 1, using: &generator),
                straighten: .random(in: -45 ... 45, using: &generator)
            )
            guard !crop.isIdentity else { continue }

            let extent = crop.apply(to: input).extent
            let size = crop.keptPixelSize(imageWidth: width, imageHeight: height)

            #expect(extent == CGRect(x: 0, y: 0, width: size.width, height: size.height), "\(crop)")
        }
    }

    /// The pin for every uncropped save: passing an identity crop changes nothing in the file.
    @Test(arguments: [UTType.jpeg, .heic])
    func anIdentityCropSavesByteIdenticalToNone(type: UTType) async throws {
        let source = try await AdjustmentFileFixtures.tagged(type, orientation: 6, in: directory)
        let plain = directory.appendingPathComponent("plain").appendingPathExtension(for: type)
        let identity = directory.appendingPathComponent("identity").appendingPathExtension(for: type)
        let adjustments = ImageAdjustmentDescription(light: .init(exposure: 0.4))

        try await renderer.renderFile(adjustments, orientation: .right, source: source, destination: plain)
        try await renderer.renderFile(adjustments, orientation: .right, crop: CropEdit(aspect: .square), source: source, destination: identity)

        #expect(try Data(contentsOf: plain) == Data(contentsOf: identity))
    }

    // MARK: - Straighten

    /// `CIStraightenFilter` turns the picture and scales it to fill its own extent, which is a centered
    /// crop at the original aspect. Ours at the same aspect, scaled back up, should be the same picture.
    /// The two differ only by resampling: a mean of 0.07 to 1.01 levels of 255 at these angles, against
    /// 13 to 24 for the opposite turn.
    @Test(arguments: [2.0, 5.0, 10.0])
    func straightenMatchesCoreImagesAtTheOriginalAspect(degrees: Double) throws {
        let source = try CGImage.contentsOf(url: TestBundleResources.shared.songbird)
        let width = source.width
        let height = source.height
        let input = CIImage(cgImage: source)

        func ours(_ degrees: Double) -> CIImage {
            let crop = CropEdit.largestCentered(aspect: Double(width) / Double(height), imageWidth: width, imageHeight: height, straighten: degrees)
            let kept = crop.apply(to: input)
            return kept.transformed(by: CGAffineTransform(
                scaleX: CGFloat(width) / kept.extent.width, y: CGFloat(height) / kept.extent.height
            ))
        }

        // Core Image's angle is counterclockwise; ours is clockwise.
        let reference = CIFilter.straighten()
        reference.inputImage = input
        reference.angle = Float(-degrees * .pi / 180)
        let expected = try #require(reference.outputImage)

        let match = try meanDifference(ours(degrees), expected, width: width, height: height)
        let opposite = try meanDifference(ours(-degrees), expected, width: width, height: height)

        #expect(match < Self.straightenTolerance, "mean difference \(match) at \(degrees)°")
        #expect(opposite > match * 4, "opposite turn \(opposite) against \(match) at \(degrees)°")
    }

    private static let straightenTolerance = 1.5

    /// Mean absolute RGB difference in levels of 255, over the picture less a 4-pixel border.
    private func meanDifference(_ a: CIImage, _ b: CIImage, width: Int, height: Int) throws -> Double {
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let first = try bytes(renderer.context.createCGImage(a, from: rect))
        let second = try bytes(renderer.context.createCGImage(b, from: rect))
        let border = 4
        var total = 0
        var count = 0

        for y in border ..< height - border {
            for x in border ..< width - border {
                let index = (y * width + x) * 4
                for channel in 0 ..< 3 {
                    total += abs(Int(first[index + channel]) - Int(second[index + channel]))
                    count += 1
                }
            }
        }

        return Double(total) / Double(count)
    }

    // MARK: - Order

    /// The vignette is placed on the kept area, so its four corners darken alike, though the crop is
    /// off center in the source.
    @Test func vignetteIsCenteredOnTheKeptArea() throws {
        let source = try flat(gray: 0.6, width: 400, height: 200)
        let crop = CropEdit(centerX: 0.2, centerY: -0.1, width: 0.5, height: 0.7)
        let output = try render(crop, adjustments: ImageAdjustmentDescription(vignette: .init(amount: 1)), source: source)
        let data = try bytes(output)
        let last = (x: output.width - 1, y: output.height - 1)

        let corners = [(0, 0), (last.x, 0), (0, last.y), (last.x, last.y)].map { pixel(data, width: output.width, x: $0, y: $1).r }
        let center = pixel(data, width: output.width, x: output.width / 2, y: output.height / 2).r

        #expect((corners.max() ?? 0) - (corners.min() ?? 0) <= 1)
        #expect((corners.max() ?? 0) < center)
    }

    /// The crop runs before the pending orientation: the same region comes out, turned.
    @Test(arguments: OrientationEdit.allCases)
    func aCropThenAnOrientationShowsTheSameRegionTurned(orientation: OrientationEdit) throws {
        let source = try quadrants()
        let crop = CropEdit(centerX: -0.1, centerY: -0.12, width: 0.6, height: 0.5)
        let upright = try render(crop, source: source)

        let turned = try bytes(render(crop, orientation: orientation, source: source))
        let expectedImage = orientation.apply(to: CIImage(cgImage: upright))
        let expected = try bytes(renderer.context.createCGImage(expectedImage, from: expectedImage.extent))

        #expect(turned == expected)
    }

    // MARK: - Entry points

    @Test func theHistogramSeesOnlyTheKeptArea() throws {
        let source = try bitmap(width: 200, height: 100) { context in
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        }
        // The right half, inset a little so no edge pixel is sampled.
        let crop = CropEdit(centerX: 0.25, width: 0.4, height: 0.8)

        let whole = try #require(renderer.levelsHistogram(ImageAdjustmentDescription(), source: source))
        let levels = try #require(renderer.levelsHistogram(ImageAdjustmentDescription(), cropEdit: crop, source: source))
        let curves = try #require(renderer.curvesHistogram(ImageAdjustmentDescription(), cropEdit: crop, source: source))

        #expect(whole.luminance[0] > 0.4)
        #expect(levels.luminance[0] == 0)
        #expect(curves.luminance[0] == 0)
    }

    @Test func theDisplayedPixelSizeOfAQuarterTurnedFileIsSwapped() async throws {
        let url = try await AdjustmentFileFixtures.tagged(.jpeg, orientation: 6, in: directory)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        let storedWidth = try #require(properties[kCGImagePropertyPixelWidth as String] as? Int)
        let storedHeight = try #require(properties[kCGImagePropertyPixelHeight as String] as? Int)

        let displayed = try #require(ImageAdjustmentRenderer.displayedPixelSize(contentsOf: url))

        #expect(storedWidth != storedHeight)
        #expect(displayed.width == storedHeight)
        #expect(displayed.height == storedWidth)
    }

    // MARK: - Perspective

    /// The crop step as it was before perspective, for the pin below.
    private func turnedAndCropped(_ crop: CropEdit, _ image: CIImage) -> CIImage {
        let extent = image.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        let kept = crop.contained(imageWidth: width, imageHeight: height)
        let size = crop.keptPixelSize(imageWidth: width, imageHeight: height)
        let topLeftCenter = kept.pixelCenter(imageWidth: width, imageHeight: height)
        let center = CGPoint(x: extent.minX + topLeftCenter.x, y: extent.maxY - topLeftCenter.y)
        let radians = -kept.straighten * .pi / 180
        let turned = image.clampedToExtent().transformed(by: CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(CGAffineTransform(rotationAngle: radians))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
        let origin = CGPoint(x: (center.x - Double(size.width) / 2).rounded(), y: (center.y - Double(size.height) / 2).rounded())
        return turned.cropped(to: CGRect(origin: origin, size: CGSize(width: size.width, height: size.height)))
            .transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
    }

    @Test func aCropWithoutPerspectiveRendersAsTheTurnAndCropAlone() throws {
        let source = try CGImage.contentsOf(url: TestBundleResources.shared.songbird)
        let input = CIImage(cgImage: source)
        let crop = CropEdit(centerX: 0.08, centerY: -0.05, width: 0.6, height: 0.55, straighten: 6, vertical: 0, horizontal: 0)

        let actual = crop.apply(to: input)
        let expected = turnedAndCropped(crop, input)
        #expect(actual.extent == expected.extent)
        #expect(try bytes(renderer.context.createCGImage(actual, from: actual.extent)) == bytes(renderer.context.createCGImage(expected, from: expected.extent)))
    }

    /// One axis alone is `CIPerspectiveRotate` at 28 mm with Photos' signs: Vertical +N is pitch -N,
    /// Horizontal +N is yaw -N. The kept rectangle of each is compared; the opposite sign is far off.
    @Test(arguments: [(10.0, 0.0), (-20, 0), (0, 15), (0, -8)])
    func oneAxisMatchesCoreImagesPerspectiveRotate(vertical: Double, horizontal: Double) throws {
        let source = try CGImage.contentsOf(url: TestBundleResources.shared.songbird)
        let input = CIImage(cgImage: source)

        func ours(_ sign: Double) -> CIImage {
            CropEdit(vertical: sign * vertical, horizontal: sign * horizontal).apply(to: input)
        }

        let kept = ours(1).extent
        let width = Double(source.width)
        let height = Double(source.height)
        let origin = CGPoint(x: ((width - kept.width) / 2).rounded(), y: ((height - kept.height) / 2).rounded())

        let reference = CIFilter.perspectiveRotate()
        reference.inputImage = input
        reference.focalLength = Float(CropEdit.perspectiveFocalLength)
        reference.pitch = Float(-vertical * .pi / 180)
        reference.yaw = Float(-horizontal * .pi / 180)
        let expected = try #require(reference.outputImage)
            .cropped(to: CGRect(origin: origin, size: kept.size))
            .transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))

        let match = try meanDifference(ours(1), expected, width: Int(kept.width), height: Int(kept.height))
        let opposite = try meanDifference(ours(-1), expected, width: Int(kept.width), height: Int(kept.height))

        #expect(match < Self.straightenTolerance, "V\(vertical) H\(horizontal): mean difference \(match)")
        #expect(opposite > match * 4, "V\(vertical) H\(horizontal): opposite sign \(opposite) against \(match)")
    }

    /// 600 × 400 white, with 3-pixel black lines every 100 pixels each way.
    private func grid() throws -> CGImage {
        try bitmap(width: 600, height: 400) { context in
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            for x in stride(from: 100, to: 600, by: 100) {
                context.fill(CGRect(x: x - 1, y: 0, width: 3, height: 400))
            }
            for y in stride(from: 100, to: 400, by: 100) {
                context.fill(CGRect(x: 0, y: y - 1, width: 600, height: 3))
            }
        }
    }

    /// The darkness-weighted center of `count` pixels from `start`, stepping by `stride`.
    private func darkCentroid(_ data: [UInt8], start: Int, stride: Int, count: Int) -> Double? {
        var total = 0.0
        var weighted = 0.0
        for index in 0 ..< count {
            let darkness = 255 - Double(data[(start + index * stride) * 4])
            total += darkness
            weighted += darkness * Double(index)
        }
        return total > 200 ? weighted / total : nil
    }

    /// A grid photographed with a tilt (the correction's inverse) comes back with straight, upright lines.
    @Test(arguments: [(10.0, 0.0), (0, -8), (10, -8)])
    func aTiltedGridComesBackStraight(vertical: Double, horizontal: Double) throws {
        let source = CIImage(cgImage: try grid())
        let crop = CropEdit(vertical: vertical, horizontal: horizontal)
        let tilt = crop.perspective(imageWidth: 600, imageHeight: 400).inverse

        func corner(_ x: Double, _ y: Double) -> CIVector {
            let p = tilt.apply(SIMD2(x, 400 - y))
            return CIVector(x: p.x, y: 400 - p.y)
        }

        let tilted = source.clampedToExtent().cropped(to: CGRect(x: -1, y: -1, width: 602, height: 402))
            .applyingFilter("CIPerspectiveTransform", parameters: [
                "inputTopLeft": corner(-1, 401), "inputTopRight": corner(601, 401),
                "inputBottomRight": corner(601, -1), "inputBottomLeft": corner(-1, -1),
            ])
            .composited(over: CIImage(color: .white))
            .cropped(to: source.extent)

        let output = crop.apply(to: tilted)
        let image = try #require(renderer.context.createCGImage(output, from: output.extent))
        let data = try bytes(image)
        let width = image.width
        let height = image.height
        // The kept rectangle's top left in the source, from `apply`'s rounding.
        let originX = Int(((600 - Double(width)) / 2).rounded())
        let originY = 400 - height - Int(((400 - Double(height)) / 2).rounded())
        let window = 12
        var lines = 0

        /// Whether a sample at `position` in the source lies clear of every line across it.
        func isClear(_ position: Int) -> Bool {
            abs(position - Int((Double(position) / 100).rounded()) * 100) > window + 2
        }

        for lineX in stride(from: 100, to: 600, by: 100) {
            let x = lineX - originX
            guard x - window >= 0, x + window < width else { continue }
            let centroids = stride(from: 6, to: height - 6, by: 9).filter { isClear($0 + originY) }.compactMap { y in
                darkCentroid(data, start: y * width + x - window, stride: 1, count: window * 2 + 1)
            }
            lines += 1
            #expect((centroids.max() ?? 0) - (centroids.min() ?? .infinity) < 1, "column \(lineX): \(centroids)")
        }

        for lineY in stride(from: 100, to: 400, by: 100) {
            let y = lineY - originY
            guard y - window >= 0, y + window < height else { continue }
            let centroids = stride(from: 6, to: width - 6, by: 9).filter { isClear($0 + originX) }.compactMap { x in
                darkCentroid(data, start: (y - window) * width + x, stride: width, count: window * 2 + 1)
            }
            lines += 1
            #expect((centroids.max() ?? 0) - (centroids.min() ?? .infinity) < 1, "row \(lineY): \(centroids)")
        }

        #expect(lines >= 4)
    }

    /// With perspective the render's size is still the size rule's, and every kept pixel is opaque.
    @Test(arguments: [(200, 100), (201, 133), (97, 160)])
    func theKeptExtentWithPerspectiveIsTheKeptPixelSizeAndOpaque(width: Int, height: Int) throws {
        let input = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        var generator = SeededGenerator(state: UInt64(width * 1000 + height + 7))

        for _ in 0 ..< 40 {
            let crop = CropEdit(
                centerX: .random(in: -0.2 ... 0.2, using: &generator),
                centerY: .random(in: -0.2 ... 0.2, using: &generator),
                width: .random(in: 0.2 ... 1, using: &generator),
                height: .random(in: 0.2 ... 1, using: &generator),
                straighten: .random(in: -20 ... 20, using: &generator),
                vertical: .random(in: -30 ... 30, using: &generator),
                horizontal: .random(in: -30 ... 30, using: &generator)
            )

            let output = crop.apply(to: input)
            let size = crop.keptPixelSize(imageWidth: width, imageHeight: height)
            #expect(output.extent == CGRect(x: 0, y: 0, width: size.width, height: size.height), "\(crop)")

            let data = try bytes(renderer.context.createCGImage(output, from: output.extent))
            let transparent = stride(from: 3, to: data.count, by: 4).filter { data[$0] != 255 }.count
            #expect(transparent == 0, "\(crop): \(transparent) pixels not opaque")
        }
    }
}
