// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import SPFKTesting
import Testing

@testable import SPFKImage

/// Rendering only part of the image, as the zoomed preview does.
@Suite(.tags(.file))
final class ImageAdjustmentViewStateTests {
    let renderer = ImageAdjustmentRenderer()
    let source: CGImage

    init() throws {
        source = try CGImage.contentsOf(url: TestBundleResources.shared.songbird)
    }

    // MARK: - Crop

    @Test(arguments: [ImageOrientationEdit.up, .right])
    func aCropMatchesTheSameRegionOfTheFullRender(orientation: ImageOrientationEdit) throws {
        // Vignette and brilliance read the whole image's extent, so a crop must not shift them.
        let adjustments = ImageAdjustmentDescription(light: .init(brilliance: 0.6, exposure: 0.3), vignette: .init(amount: 0.8))
        let full = try #require(renderer.render(adjustments, orientation: orientation, source: source))

        // Fractional, so the crop expands to whole pixels.
        let crop = CGRect(x: 101.4, y: 37.6, width: 250.3, height: 180.2)
        let cropped = try #require(renderer.render(adjustments, orientation: orientation, source: source, crop: crop))
        let expected = try #require(full.cropping(to: crop.integral))

        #expect(cropped.width == expected.width)
        #expect(cropped.height == expected.height)

        let difference = zip(try bytes(cropped), try bytes(expected)).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(difference <= 1)
    }

    @Test func aCropOutsideTheImageRendersNothing() {
        let crop = CGRect(x: CGFloat(source.width) + 10, y: 0, width: 50, height: 50)

        #expect(renderer.render(ImageAdjustmentDescription(light: .init(exposure: 1)), source: source, crop: crop) == nil)
    }

    @Test func aCropPastAnEdgeIsLimitedToTheImage() throws {
        let crop = CGRect(x: CGFloat(source.width) - 40, y: -20, width: 100, height: 60)
        let cropped = try #require(renderer.render(ImageAdjustmentDescription(light: .init(exposure: 1)), source: source, crop: crop))

        #expect(cropped.width == 40)
        #expect(cropped.height == 40)
    }

    /// RGBA8 bytes, drawn into a bitmap of the image's own size.
    private func bytes(_ image: CGImage?) throws -> [UInt8] {
        let image = try #require(image)
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)

        try data.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        return data
    }
}
