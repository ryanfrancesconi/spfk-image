// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import Testing

@testable import SPFKImage

/// Black point, white point, brightness and contrast, measured on flat gray patches.
@Suite
final class ImageAdjustmentToneStepTests {
    let context = CIContext()

    /// The sRGB-encoded gray `level` after `adjustments`.
    private func render(gray level: Double, _ adjustments: ImageAdjustmentDescription) throws -> Double {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let color = try #require(CIColor(red: level, green: level, blue: level, colorSpace: space))
        let patch = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let pixels = try ImageAdjustmentChainPinTests.floatPixels(
            ImageAdjustmentRenderer.apply(adjustments, to: patch), context: context
        )
        return Self.encode(Double(pixels[0]))
    }

    /// Linear to sRGB-encoded.
    private static func encode(_ linear: Double) -> Double {
        linear <= 0.0031308 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055
    }

    @Test func positiveBlackPointMapsItsInputToBlack() throws {
        let value = 0.6
        let input = value * ImageAdjustmentRenderer.maximumBlackPoint

        #expect(try render(gray: input, .init(light: .init(blackPoint: value))) < 0.005)
        #expect(try render(gray: input / 2, .init(light: .init(blackPoint: value))) < 0.005)
        #expect(try render(gray: input + 0.2, .init(light: .init(blackPoint: value))) > 0.1)
        #expect(abs(try render(gray: 1, .init(light: .init(blackPoint: value))) - 1) < 0.005)
    }

    @Test func positiveBlackPointHoldsTheMidTones() throws {
        let blackPoint = ImageAdjustmentDescription(light: .init(blackPoint: 1))

        #expect(abs(try render(gray: 0.5, blackPoint) - 0.45) < 0.015)
        #expect(abs(try render(gray: 0.75, blackPoint) - 0.73) < 0.015)
    }

    @Test func negativeBlackPointRaisesBlack() throws {
        let floor = try render(gray: 0, .init(light: .init(blackPoint: -1)))

        #expect(abs(floor - ImageAdjustmentRenderer.maximumBlackPoint) < 0.01)
        #expect(abs(try render(gray: 1, .init(light: .init(blackPoint: -1))) - 1) < 0.005)
    }

    @Test func positiveWhitePointMapsItsInputToWhite() throws {
        let input = 1 - ImageAdjustmentRenderer.maximumWhitePoint

        #expect(abs(try render(gray: input, .init(light: .init(whitePoint: 1))) - 1) < 0.005)
        #expect(abs(try render(gray: (1 + input) / 2, .init(light: .init(whitePoint: 1))) - 1) < 0.005)
        #expect(try render(gray: input - 0.2, .init(light: .init(whitePoint: 1))) < 0.9)
        #expect(try render(gray: 0, .init(light: .init(whitePoint: 1))) < 0.005)
    }

    @Test func negativeWhitePointLowersWhite() throws {
        let ceiling = try render(gray: 1, .init(light: .init(whitePoint: -1)))

        #expect(abs(ceiling - (1 - ImageAdjustmentRenderer.maximumWhitePoint)) < 0.01)
        #expect(try render(gray: 0, .init(light: .init(whitePoint: -1))) < 0.005)
    }

    @Test func brightnessMovesMidGrayAndHoldsBlackAndWhite() throws {
        let lift = ImageAdjustmentRenderer.maximumBrightnessLift

        #expect(abs(try render(gray: 0.5, .init(light: .init(brightness: 1))) - (0.5 + lift)) < 0.01)
        #expect(abs(try render(gray: 0.5, .init(light: .init(brightness: -1))) - (0.5 - lift)) < 0.01)

        for value in [-1.0, 1] {
            #expect(try render(gray: 0, .init(light: .init(brightness: value))) < 0.005)
            #expect(abs(try render(gray: 1, .init(light: .init(brightness: value))) - 1) < 0.005)
        }
    }

    @Test func contrastPivotsAtMidGrayAndHoldsBlackAndWhite() throws {
        for value in [-1.0, 1] {
            #expect(abs(try render(gray: 0.5, .init(light: .init(contrast: value))) - 0.5) < 0.01)
            #expect(try render(gray: 0, .init(light: .init(contrast: value))) < 0.005)
            #expect(abs(try render(gray: 1, .init(light: .init(contrast: value))) - 1) < 0.005)
        }

        #expect(abs(try render(gray: 0.25, .init(light: .init(contrast: 1))) - 0.075) < 0.01)
        #expect(abs(try render(gray: 0.75, .init(light: .init(contrast: 1))) - 0.925) < 0.01)
        #expect(try render(gray: 0.25, .init(light: .init(contrast: 0.5))) > 0.1)
        #expect(try render(gray: 0.25, .init(light: .init(contrast: -1))) > 0.35)
    }

    @Test func positiveHighlightsLiftTheUpperTonesAndHoldBlackAndWhite() throws {
        let highlights = ImageAdjustmentDescription(light: .init(highlights: 1))

        #expect(abs(try render(gray: 0.75, highlights) - 0.82) < 0.01)
        #expect(abs(try render(gray: 0.5, highlights) - 0.52) < 0.01)
        #expect(abs(try render(gray: 0.25, highlights) - 0.25) < 0.01)
        #expect(try render(gray: 0, highlights) < 0.005)
        #expect(abs(try render(gray: 1, highlights) - 1) < 0.005)
    }

    @Test func positiveShadowsLiftTheLowerTonesAndLeaveTheUpperOnes() throws {
        let shadows = ImageAdjustmentDescription(light: .init(shadows: 1))

        #expect(abs(try render(gray: 0.25, shadows) - 0.44) < 0.01)
        #expect(abs(try render(gray: 0.5, shadows) - 0.62) < 0.01)
        #expect(abs(try render(gray: 0.75, shadows) - 0.75) < 0.01)
        #expect(try render(gray: 0, shadows) < 0.005)
        #expect(abs(try render(gray: 1, shadows) - 1) < 0.005)
    }

    @Test func positiveShadowsHoldTheRatioBetweenChannels() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let color = try #require(CIColor(red: 0.3, green: 0.12, blue: 0.06, colorSpace: space))
        let patch = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let pixels = try ImageAdjustmentChainPinTests.floatPixels(
            ImageAdjustmentRenderer.apply(.init(light: .init(shadows: 1)), to: patch), context: context
        )
        let (red, green, blue) = (Self.encode(Double(pixels[0])), Self.encode(Double(pixels[1])), Self.encode(Double(pixels[2])))

        #expect(red > 0.4)
        #expect(abs(green / red - 0.4) < 0.01)
        #expect(abs(blue / red - 0.2) < 0.01)
    }

    @Test func shadowsCurveStaysIncreasing() {
        for value in [0.5, 1] {
            let curve = ImageAdjustmentRenderer.shadowsCurve(value)
            let samples = (0 ... 100).map { curve.value(at: Double($0) / 100) }
            #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
        }
    }

    @Test func toneCurvesStayIncreasingAtTheEndsOfTheirRanges() {
        for value in [-1.0, -0.5, 0.5, 1] {
            for curve in [
                ImageAdjustmentRenderer.blackPointCurve(value),
                ImageAdjustmentRenderer.whitePointCurve(value),
                ImageAdjustmentRenderer.brightnessCurve(value),
                ImageAdjustmentRenderer.contrastCurve(value),
                ImageAdjustmentRenderer.highlightsCurve(value),
            ] {
                #expect(zip(curve, curve.dropFirst()).allSatisfy { $0.x < $1.x && $0.y <= $1.y })
            }
        }
    }
}
