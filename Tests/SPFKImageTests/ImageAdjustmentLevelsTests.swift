// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import Testing

@testable import SPFKImage

/// The levels curve and the histogram drawn under it, measured on flat gray patches.
@Suite
final class ImageAdjustmentLevelsTests {
    let context = CIContext()

    private func patch(gray level: Double) throws -> CIImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let color = try #require(CIColor(red: level, green: level, blue: level, colorSpace: space))
        return CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
    }

    /// The sRGB-encoded gray `level` after `adjustments`.
    private func render(gray level: Double, _ adjustments: ImageAdjustmentDescription) throws -> Double {
        let pixels = try ImageAdjustmentChainPinTests.floatPixels(
            ImageAdjustmentRenderer.apply(adjustments, to: try patch(gray: level)), context: context
        )
        let linear = Double(pixels[0])
        return linear <= 0.0031308 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055
    }

    private func levels(_ positions: [Double]) -> ImageAdjustmentDescription {
        var adjustments = ImageAdjustmentDescription()
        adjustments.levels.positions = positions
        return adjustments
    }

    @Test func neutralLevelsLeaveGraysUnchanged() throws {
        let neutral = levels(ImageAdjustmentDescription.Levels.identity)
        #expect(neutral.levels.isNeutral)

        for gray in [0.0, 0.2, 0.5, 0.8, 1] {
            #expect(abs(try render(gray: gray, neutral) - gray) < 0.005)
        }
    }

    @Test func blackHandleMapsItsInputToBlackAndHoldsWhite() throws {
        let adjustments = levels([0.2, 0.4, 0.6, 0.8, 1])

        #expect(try render(gray: 0.2, adjustments) < 0.005)
        #expect(try render(gray: 0.1, adjustments) < 0.005)
        #expect(abs(try render(gray: 1, adjustments) - 1) < 0.005)
    }

    @Test func whiteAndMidHandlesMapTheirInputs() throws {
        let adjustments = levels([0, 0.15, 0.3, 0.55, 0.8])

        #expect(abs(try render(gray: 0.8, adjustments) - 1) < 0.005)
        #expect(abs(try render(gray: 0.3, adjustments) - 0.5) < 0.01)
        #expect(try render(gray: 0, adjustments) < 0.005)
    }

    @Test func crossedStoredPointsStillReadIncreasing() {
        var shadowPastMid = ImageAdjustmentDescription()
        shadowPastMid.levels.shadow = 0.6

        var blackPastWhite = ImageAdjustmentDescription()
        blackPastWhite.levels.black = 1
        blackPastWhite.levels.white = -1
        blackPastWhite.levels.mid = 0.5

        for adjustments in [shadowPastMid, blackPastWhite] {
            let positions = adjustments.levels.positions
            let gap = ImageAdjustmentDescription.Levels.minimumGap

            for (lower, upper) in zip(positions, positions.dropFirst()) {
                #expect(upper - lower >= gap - 1e-12)
            }
            #expect(positions.allSatisfy { (0 ... 1).contains($0) })
        }

        #expect(shadowPastMid.levels.positions[2] == 0.5)
    }

    @Test func levelsRenderAfterBlackPoint() throws {
        let gray = 0.4
        var adjustments = levels([0.2, 0.4, 0.6, 0.8, 1])
        adjustments.light.blackPoint = -1

        // Black point first raises 0.4 to 0.55; levels then maps that, not 0.4.
        let raised = ImageAdjustmentRenderer.maximumBlackPoint + (1 - ImageAdjustmentRenderer.maximumBlackPoint) * gray
        let expected = try render(gray: raised, levels([0.2, 0.4, 0.6, 0.8, 1]))

        #expect(abs(try render(gray: gray, adjustments) - expected) < 0.01)
    }

    // MARK: - Histogram

    private func histogram(gray level: Double, _ adjustments: ImageAdjustmentDescription) throws -> ImageHistogram {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let image = try patch(gray: level)
        let source = try #require(context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: space))
        return try #require(ImageAdjustmentRenderer(context: context).levelsHistogram(adjustments, source: source))
    }

    private func peak(_ bins: [Float]) -> Int {
        bins.indices.max { bins[$0] < bins[$1] } ?? -1
    }

    @Test func histogramBinsEncodedValues() throws {
        let result = try histogram(gray: 0.5, ImageAdjustmentDescription())

        for channel in [result.red, result.green, result.blue, result.luminance] {
            #expect(channel.count == ImageHistogram.binCount)
            #expect(abs(channel.reduce(0, +) - 1) < 0.001)
            #expect((126 ... 129).contains(peak(channel)))
        }
    }

    @Test func histogramShowsWhatLevelsReceives() throws {
        let plain = try histogram(gray: 0.5, ImageAdjustmentDescription())

        let withLevels = try histogram(gray: 0.5, levels([0.3, 0.4, 0.5, 0.6, 0.7]))
        #expect(withLevels == plain)

        var exposed = ImageAdjustmentDescription(light: .init(exposure: 1))
        exposed.bypassed = []
        let brighter = try histogram(gray: 0.5, exposed)
        #expect(peak(brighter.luminance) > peak(plain.luminance) + 20)

        exposed.bypassed = [.exposure]
        #expect(try histogram(gray: 0.5, exposed) == plain)
    }

    @Test func histogramIncludesTheWhitePoint() throws {
        let plain = try histogram(gray: 0.5, ImageAdjustmentDescription())
        let lowered = try histogram(gray: 0.5, ImageAdjustmentDescription(light: .init(whitePoint: -1)))
        #expect(peak(lowered.luminance) < peak(plain.luminance) - 20)
    }

    /// Every combination of each offset at either end of its range still reads strictly increasing.
    @Test func everyRangeCornerReadsIncreasing() {
        let levels = ImageAdjustmentDescription.Group.levels.parameters
        let gap = ImageAdjustmentDescription.Levels.minimumGap

        for corner in 0 ..< (1 << levels.count) {
            var adjustments = ImageAdjustmentDescription()
            for (bit, parameter) in levels.enumerated() {
                adjustments[parameter] = corner & (1 << bit) == 0 ? parameter.range.lowerBound : parameter.range.upperBound
            }

            let positions = adjustments.levels.positions
            #expect(zip(positions, positions.dropFirst()).allSatisfy { $1 - $0 >= gap - 1e-12 }, "corner \(corner)")
            #expect(positions.allSatisfy { (0 ... 1).contains($0) }, "corner \(corner)")
        }
    }
}
