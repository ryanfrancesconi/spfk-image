// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import simd

/// Negative Vibrance: a color with its Oklch chroma scaled toward ``residual`` by `−amount`, holding
/// lightness and hue. Skin hues keep ``skinProtection`` of what they would lose.
struct MutedVibranceTransform: ColorCubeTransform {
    let amount: Double

    func callAsFunction(_ node: ColorCubeNode) -> SIMD3<Double> {
        let chroma = simd_length(SIMD2(node.oklab.y, node.oklab.z))
        guard chroma > 0 else { return node.rgb }

        let skin = HueBands.weight(hue: node.hue, center: Self.skinHue, width: Self.skinWidth)
        let scale = 1 + amount * (1 - Self.residual) * (1 - Self.skinProtection * skin)

        return ColorMath.sRGB(lightness: node.oklab.x, chroma: chroma * scale, hue: node.hue)
    }

    // MARK: - Mapping from slider positions

    /// The share of its chroma a color away from skin keeps at full negative Vibrance.
    static let residual: Double = 0.15
    /// The share of the mute a color at ``skinHue`` is spared.
    static let skinProtection: Double = 0.75
    /// Oklch hue, in degrees, of the skin tones negative Vibrance spares most.
    static let skinHue: Double = 60
    /// Oklch degrees from ``skinHue`` at which the protection reaches 0.
    static let skinWidth: Double = 50
}
