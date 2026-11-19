// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// Positive Shadows: each pixel's brightest channel moved along
/// ImageAdjustmentRenderer/shadowsCurve(_:), the other two scaled by the same ratio, so hue holds
/// and no channel passes 1.
struct ShadowsTransform: ColorCubeTransform {
    let value: Double
    private let curve: MonotoneCubicInterpolation

    init(_ value: Double) {
        self.value = value
        curve = ImageAdjustmentRenderer.shadowsCurve(value)
    }

    /// Equal when `value` is: the curve is built from it.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value
    }

    func callAsFunction(_ node: ColorCubeNode) -> SIMD3<Double> {
        let rgb = node.rgb
        let peak = rgb.max()
        guard peak > 0 else { return rgb }
        return rgb * (curve.value(at: peak) / peak)
    }
}
