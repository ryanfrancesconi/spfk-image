// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// A color plus each range's tint, in `ColorGradingRange` order, weighed by the pixel's luma. The
/// weights are the quadratic Bernstein basis of the luma raised to `2^−balance`, so they always sum
/// to 1 and positive balance favors highlights. The sum is shortened just enough to stay in 0…1,
/// which keeps luma and hue and leaves black and white untouched.
struct ColorGradingTransform: ColorCubeTransform {
    /// One per range, from ``tint(hue:saturation:)``.
    let tints: [SIMD3<Double>]
    let balance: Double

    init(tints: [SIMD3<Double>], balance: Double) {
        self.tints = tints
        self.balance = balance
    }

    init(_ grading: ImageAdjustmentDescription.ColorGrading) {
        self.init(
            tints: ImageAdjustmentDescription.ColorGradingRange.allCases.map { range in
                Self.tint(hue: grading[range].hue, saturation: grading[range].saturation)
            },
            balance: grading.balance
        )
    }

    func callAsFunction(_ node: ColorCubeNode) -> SIMD3<Double> {
        let rgb = node.rgb
        let luma = min(max((rgb * ColorMath.luminanceWeights).sum(), 0), 1)
        let t = pow(luma, pow(2, -balance))
        let weights = [(1 - t) * (1 - t), 2 * t * (1 - t), t * t]

        var offset = SIMD3<Double>.zero
        for (weight, tint) in zip(weights, tints) {
            offset += weight * tint
        }

        var scale = 1.0
        for channel in 0 ..< 3 {
            if offset[channel] > 0 {
                scale = min(scale, (1 - rgb[channel]) / offset[channel])
            } else if offset[channel] < 0 {
                scale = min(scale, rgb[channel] / -offset[channel])
            }
        }

        return rgb + max(0, scale) * offset
    }

    /// The offset toward `hue` with no luma of its own, so adding it keeps a pixel's luma. `hue` is 0…1
    /// around the HSL circle; full `saturation` has a chroma of ``maximumChroma``.
    static func tint(hue: Double, saturation: Double) -> SIMD3<Double> {
        guard saturation > 0 else { return .zero }

        let color = ColorMath.rgb(hue: hue * 360, saturation: 1, lightness: 0.5)
        let luma = (color * ColorMath.luminanceWeights).sum()
        return (color - SIMD3(repeating: luma)) * saturation * maximumChroma
    }

    // MARK: - Mapping from slider positions

    /// The chroma, max − min of sRGB-encoded channels, that a range's full saturation adds.
    static let maximumChroma: Double = 0.25
}
