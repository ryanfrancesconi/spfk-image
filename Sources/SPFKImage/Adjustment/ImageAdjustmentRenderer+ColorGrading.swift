// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation

extension ImageAdjustmentRenderer {
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
            let offset = ColorGradingTransform.tint(hue: swept.hue, saturation: swept.saturation)
            return ColorGradingTransform(tints: [offset, offset, offset], balance: 0)(gray)
        }
    }
}
