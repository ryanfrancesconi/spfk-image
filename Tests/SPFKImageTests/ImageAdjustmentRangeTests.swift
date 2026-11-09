// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
@testable import SPFKImage
import Testing

/// Steps built on Core Image's clamping filters must still pass through what a Display P3 or HDR
/// source holds outside 0…1, and keep the source's alpha.
@Suite("Adjustment value range")
struct ImageAdjustmentRangeTests {
    let context = CIContext()
    let extent = CGRect(x: 0, y: 0, width: 64, height: 64)

    private func flat(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) throws -> CIImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let color = try #require(CIColor(red: red, green: green, blue: blue, alpha: alpha, colorSpace: space))
        return CIImage(color: color).cropped(to: extent)
    }

    /// Premultiplied RGBA in extended linear sRGB, one pixel after another.
    private func pixels(_ adjustments: ImageAdjustmentDescription, _ image: CIImage) throws -> [SIMD4<Float>] {
        let floats = try ImageAdjustmentChainPinTests.floatPixels(
            ImageAdjustmentRenderer.apply(adjustments, to: image), context: context
        )
        return stride(from: 0, to: floats.count, by: 4).map {
            SIMD4(floats[$0], floats[$0 + 1], floats[$0 + 2], floats[$0 + 3])
        }
    }

    @Test func grainKeepsTheSourcesTransparency() throws {
        let output = try pixels(.init(grain: 1), flat(0.4, 0.3, 0.2, alpha: 0.5))
        #expect(output.allSatisfy { abs($0.w - 0.5) < 0.001 })
    }

    /// Black and white take no grain, so channels beyond them are left exactly as they were.
    @Test func grainPassesWideGamutAndHDRChannelsThrough() throws {
        let output = try pixels(.init(grain: 1), flat(-0.1, 1.3, 0.05))
        #expect(output.allSatisfy { abs($0.x - -0.1) < 0.001 && abs($0.y - 1.3) < 0.001 })
    }

    /// A gray takes no selective shift, so an HDR gray keeps its level.
    @Test func selectiveColorPassesAnHDRGrayThrough() throws {
        let output = try pixels(.init(selectiveRedSaturation: -1), flat(1.5, 1.5, 1.5))
        #expect(output.allSatisfy { abs($0.x - 1.5) < 0.005 && abs($0.y - 1.5) < 0.005 && abs($0.z - 1.5) < 0.005 })
    }

    /// A shift in a distant band leaves a wide-gamut green where it was.
    @Test func selectiveColorPassesAWideGamutGreenThrough() throws {
        let output = try pixels(.init(selectiveBlueLuminance: 1), flat(-0.1, 1.3, 0.05))
        #expect(output.allSatisfy { abs($0.x - -0.1) < 0.005 && abs($0.y - 1.3) < 0.005 && abs($0.z - 0.05) < 0.005 })
    }

    /// Color Grading leaves white untouched, so an HDR white keeps its level.
    @Test func colorGradingPassesAnHDRWhiteThrough() throws {
        let output = try pixels(.init(colorGradingHighlightSaturation: 1), flat(1.5, 1.5, 1.5))
        #expect(output.allSatisfy { abs($0.x - 1.5) < 0.005 && abs($0.y - 1.5) < 0.005 && abs($0.z - 1.5) < 0.005 })
    }
}
