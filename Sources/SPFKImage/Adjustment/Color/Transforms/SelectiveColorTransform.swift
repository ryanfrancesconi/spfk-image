// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import simd

/// A color with each band's hue, saturation and luminance shift, in `ColorBand` order, weighed by
/// HueBands/weight(hue:center:width:) at that band's width. The shift also scales with chroma,
/// from none at HueBands/minimumChroma to all of it at `selectiveColorFullChroma`, so grays and
/// near-grays, whose hue is noise, do not move. Luminance scales with chroma again, so a dull color
/// moves less than a vivid one.
struct SelectiveColorTransform: ColorCubeTransform {
    let shifts: [SIMD3<Double>]
    /// One per entry of `shifts`.
    let widths: [Double]

    init(shifts: [SIMD3<Double>], widths: [Double]) {
        self.shifts = shifts
        self.widths = widths
    }

    /// Every band at HueBands/defaultWidth.
    init(shifts: [SIMD3<Double>]) {
        self.init(shifts: shifts, widths: Array(repeating: HueBands.defaultWidth, count: shifts.count))
    }

    init(_ selectiveColor: ImageAdjustmentDescription.SelectiveColor) {
        typealias ColorBand = ImageAdjustmentDescription.ColorBand

        self.init(
            shifts: ColorBand.allCases.map { band in
                SIMD3(selectiveColor[band].hue, selectiveColor[band].saturation, selectiveColor[band].luminance)
            },
            widths: ColorBand.allCases.map { HueBands.width(range: selectiveColor[$0].range) }
        )
    }

    func callAsFunction(_ node: ColorCubeNode) -> SIMD3<Double> {
        typealias Renderer = ImageAdjustmentRenderer

        guard node.chroma > HueBands.minimumChroma else { return node.rgb }

        var shift = SIMD3<Double>.zero
        for (index, bandShift) in shifts.enumerated() where bandShift != .zero {
            shift += HueBands.weight(hue: node.hue, center: HueBands.centers[index], width: widths[index]) * bandShift
        }
        shift *= HueBands.chromaGate(node.chroma, full: Renderer.selectiveColorFullChroma)

        guard shift != .zero else { return node.rgb }

        var lightness = node.oklab.x
        var chroma = simd_length(SIMD2(node.oklab.y, node.oklab.z))
        let hue = node.hue + shift.x * Renderer.maximumSelectiveHueShift

        // A turned color takes its share of the new hue's most colorful sRGB color, and part of the
        // way toward that color's lightness: yellow held at its own lightness has no orange to become.
        if shift.x != 0 {
            let from = ColorMath.sRGBCusp(hue: node.hue)
            let to = ColorMath.sRGBCusp(hue: hue)
            let share = chroma / from.y
            lightness += Renderer.selectiveHueLightnessShare * share * (to.x - from.x)
            chroma = share * to.y
        }

        chroma *= max(0, 1 + shift.y)
        lightness += shift.z * node.chroma * (shift.z > 0 ? Renderer.maximumSelectiveLightening : Renderer.maximumSelectiveDarkening)

        return ColorMath.sRGB(lightness: lightness, chroma: chroma, hue: hue)
    }
}
