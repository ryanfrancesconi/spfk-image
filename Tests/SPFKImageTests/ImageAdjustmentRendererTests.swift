// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import SPFKTesting
import Testing

@testable import SPFKImage

@Suite(.tags(.file))
final class ImageAdjustmentRendererTests {
    let renderer = ImageAdjustmentRenderer()
    let source: CGImage
    let sourceStatistics: ImageStatistics

    init() throws {
        source = try CGImage.contentsOf(url: TestBundleResources.shared.songbird)
        sourceStatistics = try #require(ImageStatistics(source))
    }

    private func statistics(_ adjustments: ImageAdjustmentDescription) throws -> ImageStatistics {
        let rendered = try #require(renderer.render(adjustments, source: source))
        return try #require(ImageStatistics(rendered))
    }

    @Test func neutralRenderMatchesTheSource() throws {
        let rendered = try statistics(ImageAdjustmentDescription())

        #expect(rendered.width == sourceStatistics.width)
        #expect(rendered.height == sourceStatistics.height)
        #expect(abs(rendered.meanLuminance - sourceStatistics.meanLuminance) < 0.5)
        #expect(abs(rendered.meanChannelSpread - sourceStatistics.meanChannelSpread) < 0.5)
    }

    @Test func exposureMovesMeanLuminance() throws {
        #expect(try statistics(ImageAdjustmentDescription(exposure: 1)).meanLuminance > sourceStatistics.meanLuminance)
        #expect(try statistics(ImageAdjustmentDescription(exposure: -1)).meanLuminance < sourceStatistics.meanLuminance)
    }

    @Test func contrastMovesLuminanceSpread() throws {
        let raised = try statistics(ImageAdjustmentDescription(contrast: 0.5))
        let lowered = try statistics(ImageAdjustmentDescription(contrast: -0.5))

        #expect(raised.luminanceStandardDeviation > sourceStatistics.luminanceStandardDeviation)
        #expect(lowered.luminanceStandardDeviation < sourceStatistics.luminanceStandardDeviation)
    }

    @Test func minimumSaturationRemovesColor() throws {
        let desaturated = try statistics(ImageAdjustmentDescription(saturation: -1))

        #expect(desaturated.meanChannelSpread < 2)
        #expect(sourceStatistics.meanChannelSpread > 10)
    }

    @Test func warmerTemperatureRaisesRedAgainstBlue() throws {
        let warm = try statistics(ImageAdjustmentDescription(temperature: 0.5))
        let cool = try statistics(ImageAdjustmentDescription(temperature: -0.5))
        let sourceBalance = sourceStatistics.meanRed - sourceStatistics.meanBlue

        #expect(warm.meanRed - warm.meanBlue > sourceBalance)
        #expect(cool.meanRed - cool.meanBlue < sourceBalance)
    }

    @Test func positiveTintMovesAwayFromGreen() throws {
        func greenBalance(_ s: ImageStatistics) -> Double { s.meanGreen - (s.meanRed + s.meanBlue) / 2 }

        let magenta = try statistics(ImageAdjustmentDescription(tint: 0.5))
        let green = try statistics(ImageAdjustmentDescription(tint: -0.5))

        #expect(greenBalance(magenta) < greenBalance(sourceStatistics))
        #expect(greenBalance(green) > greenBalance(sourceStatistics))
    }

    @Test func loweredHighlightsDarkenTheBrightestPixels() throws {
        let recovered = try statistics(ImageAdjustmentDescription(highlights: -1))

        #expect(recovered.brightLuminance < sourceStatistics.brightLuminance)
    }

    @Test func raisedShadowsLiftTheDarkestPixels() throws {
        let lifted = try statistics(ImageAdjustmentDescription(shadows: 1))

        #expect(lifted.darkLuminance > sourceStatistics.darkLuminance)
    }

    @Test func sepiaOrdersChannelsRedGreenBlue() throws {
        let toned = try statistics(ImageAdjustmentDescription(sepia: 1))

        #expect(toned.meanRed > toned.meanGreen)
        #expect(toned.meanGreen > toned.meanBlue)
    }

    @Test func sharpnessRaisesEdgeEnergy() throws {
        let sharpened = try statistics(ImageAdjustmentDescription(sharpness: 1))

        #expect(sharpened.edgeEnergy > sourceStatistics.edgeEnergy)
    }

    @Test func chainAppliesExposureBeforeContrast() throws {
        let input = CIImage(cgImage: source)
        let combined = ImageAdjustmentRenderer.apply(ImageAdjustmentDescription(exposure: 1, contrast: 0.8), to: input)
        let exposureFirst = ImageAdjustmentRenderer.apply(
            ImageAdjustmentDescription(contrast: 0.8),
            to: ImageAdjustmentRenderer.apply(ImageAdjustmentDescription(exposure: 1), to: input)
        )
        let contrastFirst = ImageAdjustmentRenderer.apply(
            ImageAdjustmentDescription(exposure: 1),
            to: ImageAdjustmentRenderer.apply(ImageAdjustmentDescription(contrast: 0.8), to: input)
        )

        let combinedLuminance = try meanLuminance(combined)
        #expect(abs(combinedLuminance - (try meanLuminance(exposureFirst))) < 0.5)
        #expect(abs(combinedLuminance - (try meanLuminance(contrastFirst))) > 2)
    }

    @Test func renderKeepsADisplayP3ColorSpace() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let p3Source = try #require(renderer.context.createCGImage(
            CIImage(cgImage: source), from: CIImage(cgImage: source).extent, format: .RGBA8, colorSpace: p3
        ))

        let rendered = try #require(renderer.render(ImageAdjustmentDescription(exposure: 0.5), source: p3Source))

        #expect(rendered.colorSpace?.name == CGColorSpace.displayP3)
    }

    private func meanLuminance(_ image: CIImage) throws -> Double {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let cgImage = try #require(renderer.context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: space))
        return try #require(ImageStatistics(cgImage)).meanLuminance
    }
}
