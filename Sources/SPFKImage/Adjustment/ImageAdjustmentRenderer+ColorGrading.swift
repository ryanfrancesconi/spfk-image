// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation

extension ImageAdjustmentRenderer {
    static func colorGrading(_ image: CIImage, _ grading: ImageAdjustmentDescription.ColorGrading) -> CIImage {
        ColorCube.apply(ColorGradingTransform(grading), to: image)
    }

    /// The offset toward `hue` with no luma of its own, so adding it keeps a pixel's luma. `hue` is 0…1
    /// around the HSL circle; full `saturation` has a chroma of ``maximumColorGradingChroma``.
    static func colorGradingTint(hue: Double, saturation: Double) -> SIMD3<Double> {
        guard saturation > 0 else { return .zero }

        let color = ColorMath.rgb(hue: hue * 360, saturation: 1, lightness: 0.5)
        let luma = (color * ColorMath.luminanceWeights).sum()
        return (color - SIMD3(repeating: luma)) * saturation * maximumColorGradingChroma
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
            return ColorGradingTransform(tints: [offset, offset, offset], balance: 0)(gray)
        }
    }

    // MARK: - Mapping from slider positions

    /// The chroma, max − min of sRGB-encoded channels, that a range's full saturation adds.
    static let maximumColorGradingChroma: Double = 0.25
}
