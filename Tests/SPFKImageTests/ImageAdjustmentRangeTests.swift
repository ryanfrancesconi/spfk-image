// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
@testable import SPFKImage
import Testing

/// Steps built on Core Image's blend modes must keep the source's alpha.
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
}
