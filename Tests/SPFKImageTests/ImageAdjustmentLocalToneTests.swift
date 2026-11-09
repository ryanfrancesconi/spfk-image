// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import SPFKTesting
import Testing

@testable import SPFKImage

/// Brilliance and Definition.
@Suite(.tags(.file))
final class ImageAdjustmentLocalToneTests {
    let renderer = ImageAdjustmentRenderer()
    let source: CGImage

    init() throws {
        source = try CGImage.contentsOf(url: TestBundleResources.shared.songbird)
    }

    private func statistics(_ adjustments: ImageAdjustmentDescription) throws -> ImageStatistics {
        let rendered = try #require(renderer.render(adjustments, source: source))
        return try #require(ImageStatistics(rendered))
    }

    @Test func positiveBrillianceLiftsMidTonesMoreThanHighlights() throws {
        let neutral = try statistics(ImageAdjustmentDescription())
        let lifted = try statistics(ImageAdjustmentDescription(light: .init(brilliance: 1)))

        let midGain = lifted.medianLuminance - neutral.medianLuminance
        #expect(midGain > 10)
        #expect(lifted.brightLuminance - neutral.brightLuminance < midGain)
    }

    @Test func negativeBrillianceLowersMidTonesMoreThanHighlights() throws {
        let neutral = try statistics(ImageAdjustmentDescription())
        let lowered = try statistics(ImageAdjustmentDescription(light: .init(brilliance: -1)))

        let midDrop = neutral.medianLuminance - lowered.medianLuminance
        #expect(midDrop > 10)
        #expect(neutral.brightLuminance - lowered.brightLuminance < midDrop)
    }

    @Test func definitionRaisesLocalContrast() throws {
        let neutral = try statistics(ImageAdjustmentDescription())
        let defined = try statistics(ImageAdjustmentDescription(detail: .init(definition: 1)))
        #expect(defined.edgeEnergy > neutral.edgeEnergy * 1.5)
    }

    @Test func localToneKeepsTheHue() throws {
        let neutral = try statistics(ImageAdjustmentDescription())
        for adjustments in [ImageAdjustmentDescription(light: .init(brilliance: 1)), ImageAdjustmentDescription(detail: .init(definition: 1))] {
            let adjusted = try statistics(adjustments)
            // Red against green: the songbird is a yellow bird on green.
            let neutralRatio = neutral.meanRed / neutral.meanGreen
            let adjustedRatio = adjusted.meanRed / adjusted.meanGreen
            #expect(abs(adjustedRatio - neutralRatio) < 0.05)
        }
    }

    /// Core Image's blend modes clamp each channel to 0…1, which would clip a color outside sRGB; a
    /// fractional base size leaves an artifact in the last column. The flat image has no detail, so
    /// only Definition's slight darkening of the base remains, and every channel scales by the same
    /// ratio.
    @Test func definitionKeepsAFlatWideGamutColorsChannelRatios() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let color = try #require(CIColor(red: -0.1, green: 0.8, blue: 0.05, alpha: 1, colorSpace: space))
        let flat = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))

        let context = CIContext()
        let before = try ImageAdjustmentChainPinTests.floatPixels(flat, context: context)
        let after = try ImageAdjustmentChainPinTests.floatPixels(
            ImageAdjustmentRenderer.apply(ImageAdjustmentDescription(detail: .init(definition: 1)), to: flat), context: context
        )
        // Channel ratios survive: the negative red channel stays negative and proportional to green.
        let ratios = stride(from: 0, to: after.count, by: 4).map { after[$0] / after[$0 + 1] }
        let expected = before[0] / before[1]
        #expect(ratios.allSatisfy { abs($0 - expected) < 0.01 }, "\(ratios.min() ?? 0)…\(ratios.max() ?? 0)")
        let greenChange = stride(from: 1, to: after.count, by: 4).map { abs(after[$0] - before[$0]) }.max() ?? 0
        #expect(greenChange < 0.05, "\(greenChange)")
    }

    @Test func brillianceCurveHoldsBlackAndWhiteAndStaysIncreasing() {
        for value in [-1.0, 1] {
            let curve = ImageAdjustmentRenderer.brillianceCurve(value)
            #expect(curve.first?.y == 0)
            #expect(curve.last?.y == 1)
            #expect(zip(curve, curve.dropFirst()).allSatisfy { $0.y < $1.y })
        }
    }
}
