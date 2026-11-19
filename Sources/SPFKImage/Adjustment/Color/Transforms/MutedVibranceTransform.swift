// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import simd

/// Negative Vibrance: a color with its Oklch chroma scaled toward `vibranceResidual` by `−amount`,
/// holding lightness and hue. Skin hues keep `vibranceSkinProtection` of what they would lose.
struct MutedVibranceTransform: ColorCubeTransform {
    let amount: Double

    func callAsFunction(_ node: ColorCubeNode) -> SIMD3<Double> {
        typealias Renderer = ImageAdjustmentRenderer

        let chroma = simd_length(SIMD2(node.oklab.y, node.oklab.z))
        guard chroma > 0 else { return node.rgb }

        let skin = HueBands.weight(hue: node.hue, center: Renderer.vibranceSkinHue, width: Renderer.vibranceSkinWidth)
        let scale = 1 + amount * (1 - Renderer.vibranceResidual) * (1 - Renderer.vibranceSkinProtection * skin)

        return ColorMath.sRGB(lightness: node.oklab.x, chroma: chroma * scale, hue: node.hue)
    }
}
