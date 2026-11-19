// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// Positive Shadows: each pixel's brightest channel moved along ``curve(_:)``, the other two scaled by
/// the same ratio, so hue holds and no channel passes 1.
struct ShadowsTransform: ColorCubeTransform {
    let value: Double
    private let interpolation: MonotoneCubicInterpolation

    init(_ value: Double) {
        self.value = value
        interpolation = Self.curve(value)
    }

    /// Equal when `value` is: the curve is built from it.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value
    }

    func callAsFunction(_ node: ColorCubeNode) -> SIMD3<Double> {
        let rgb = node.rgb
        let peak = rgb.max()
        guard peak > 0 else { return rgb }
        return rgb * (interpolation.value(at: peak) / peak)
    }

    /// Lifts the lower tones by ``lift``, so black and white stay fixed.
    static func curve(_ value: Double) -> MonotoneCubicInterpolation {
        MonotoneCubicInterpolation(x: ToneCurve.positions, y: zip(ToneCurve.positions, lift).map { $0 + value * $1 })
    }

    // MARK: - Mapping from slider positions

    /// How far full positive Shadows moves each of `ToneCurve.positions`, in sRGB-encoded values.
    static let lift: [Double] = [0, 0.19, 0.12, 0, 0]
}
