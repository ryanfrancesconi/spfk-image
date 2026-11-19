// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import simd

extension ImageAdjustmentRenderer {
    typealias ColorBand = ImageAdjustmentDescription.ColorBand

    /// The colors `band`'s reference color takes as `component` moves across its range, from minimum to
    /// maximum, with `shift`'s other components applied. sRGB-encoded, as the renderer works. Range
    /// does not change the reference, which sits on the band's center, so its track is one color.
    public static func selectiveColorTrack(
        _ band: ImageAdjustmentDescription.ColorBand,
        component: ImageAdjustmentDescription.SelectiveColor.Component,
        shift: ImageAdjustmentDescription.SelectiveColor.Shift,
        stops: Int = 25
    ) -> [SIMD3<Double>] {
        let reference = HueBands.reference(band)
        let range = band.parameter(component).range
        let count = max(2, stops)

        return (0 ..< count).map { stop in
            var swept = shift
            swept[component] = range.lowerBound + (range.upperBound - range.lowerBound) * Double(stop) / Double(count - 1)

            let shifts = ColorBand.allCases.map { $0 == band ? SIMD3(swept.hue, swept.saturation, swept.luminance) : .zero }
            return SelectiveColorTransform(shifts: shifts)(reference)
        }
    }
}
