// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation

extension ImageAdjustmentRenderer {
    typealias ColorGradingRange = ImageAdjustmentDescription.ColorGradingRange

    static func colorGrading(_ image: CIImage, _ grading: ImageAdjustmentDescription.ColorGrading) -> CIImage {
        let values = ColorGradingRange.allCases.flatMap { [grading[$0].hue, grading[$0].saturation] } + [grading.balance]
        let tints = ColorGradingRange.allCases.map { range in
            colorGradingTint(hue: grading[range].hue, saturation: grading[range].saturation)
        }
        let balance = grading.balance

        return colorCube(image, step: "colorGrading", values: values) { colorGrading($0, tints: tints, balance: balance) }
    }

    /// The offset toward `hue` with no luma of its own, so adding it keeps a pixel's luma. `hue` is 0…1
    /// around the HSL circle; full `saturation` has a chroma of ``maximumColorGradingChroma``.
    static func colorGradingTint(hue: Double, saturation: Double) -> SIMD3<Double> {
        guard saturation > 0 else { return .zero }

        let color = ColorMath.rgb(hue: hue * 360, saturation: 1, lightness: 0.5)
        let luma = (color * ColorMath.luminanceWeights).sum()
        return (color - SIMD3(repeating: luma)) * saturation * maximumColorGradingChroma
    }

    /// `rgb` plus each range's tint, in ``ColorGradingRange`` order, weighed by the pixel's luma. The
    /// weights are the quadratic Bernstein basis of the luma raised to `2^−balance`, so they always sum
    /// to 1 and positive balance favors highlights. The sum is shortened just enough to stay in 0…1,
    /// which keeps luma and hue and leaves black and white untouched.
    static func colorGrading(_ rgb: SIMD3<Double>, tints: [SIMD3<Double>], balance: Double) -> SIMD3<Double> {
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

    /// The colors a mid gray takes as `component` moves across 0…1, its range, with `tint`'s other value
    /// applied. The Hue track is drawn at full saturation whatever `tint` holds, since hue alone renders
    /// nothing. sRGB-encoded, as the renderer works.
    public static func colorGradingTrack(
        component: ImageAdjustmentDescription.ColorGrading.Component,
        tint: ImageAdjustmentDescription.ColorGrading.Tint,
        stops: Int = 25
    ) -> [SIMD3<Double>] {
        let gray = SIMD3<Double>(repeating: 0.5)
        let count = max(2, stops)
        var swept = tint
        if component == .hue { swept.saturation = 1 }

        return (0 ..< count).map { stop in
            swept[component] = Double(stop) / Double(count - 1)
            let offset = colorGradingTint(hue: swept.hue, saturation: swept.saturation)
            return colorGrading(gray, tints: [offset, offset, offset], balance: 0)
        }
    }

    // MARK: - Mapping from slider positions

    /// The chroma, max − min of sRGB-encoded channels, that a range's full saturation adds.
    static let maximumColorGradingChroma: Double = 0.25
}
