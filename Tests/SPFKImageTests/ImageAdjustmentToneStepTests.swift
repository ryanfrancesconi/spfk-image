// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import Testing

@testable import SPFKImage

/// Black point and brightness, measured on flat gray patches.
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

        #expect(try render(gray: input, .init(blackPoint: value)) < 0.005)
        #expect(try render(gray: input / 2, .init(blackPoint: value)) < 0.005)
        #expect(try render(gray: input + 0.2, .init(blackPoint: value)) > 0.1)
        #expect(abs(try render(gray: 1, .init(blackPoint: value)) - 1) < 0.005)
    }

    @Test func negativeBlackPointRaisesBlack() throws {
        let floor = try render(gray: 0, .init(blackPoint: -1))

        #expect(abs(floor - ImageAdjustmentRenderer.maximumBlackPoint) < 0.01)
        #expect(abs(try render(gray: 1, .init(blackPoint: -1)) - 1) < 0.005)
    }

    @Test func brightnessMovesMidGrayAndHoldsBlackAndWhite() throws {
        let lift = ImageAdjustmentRenderer.maximumBrightnessLift

        #expect(abs(try render(gray: 0.5, .init(brightness: 1)) - (0.5 + lift)) < 0.01)
        #expect(abs(try render(gray: 0.5, .init(brightness: -1)) - (0.5 - lift)) < 0.01)

        for value in [-1.0, 1] {
            #expect(try render(gray: 0, .init(brightness: value)) < 0.005)
            #expect(abs(try render(gray: 1, .init(brightness: value)) - 1) < 0.005)
        }
    }

    @Test func toneCurvesStayIncreasingAtTheEndsOfTheirRanges() {
        for value in [-1.0, -0.5, 0.5, 1] {
            for curve in [ImageAdjustmentRenderer.blackPointCurve(value), ImageAdjustmentRenderer.brightnessCurve(value)] {
                #expect(zip(curve, curve.dropFirst()).allSatisfy { $0.x < $1.x && $0.y <= $1.y })
            }
        }
    }
}
