// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import simd

/// Positive Saturation: a Display P3-encoded color with its Oklch chroma scaled by
/// `1 + amount × maximumSaturationGain`, holding lightness and hue. A color the scale takes outside
/// Display P3 stops at its edge, so dull colors gain the most.
struct SaturationTransform: ColorCubeTransform {
    static let space = ColorCubeSpace.displayP3

    let amount: Double

    func callAsFunction(_ node: ColorCubeNode) -> SIMD3<Double> {
        let chroma = simd_length(SIMD2(node.oklab.y, node.oklab.z))
        guard chroma > 0 else { return node.rgb }

        let target = chroma * (1 + amount * ImageAdjustmentRenderer.maximumSaturationGain)
        return ColorMath.displayP3(lightness: node.oklab.x, chroma: target, hue: node.hue, insideChroma: chroma)
    }
}
