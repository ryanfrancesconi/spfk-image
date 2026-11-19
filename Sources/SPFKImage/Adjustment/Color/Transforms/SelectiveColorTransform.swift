// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import simd

/// A color with each band's hue, saturation and luminance shift, in `ColorBand` order, weighed by
/// HueBands/weight(hue:center:width:) at that band's width. The shift also scales with chroma,
/// from none at HueBands/minimumChroma to all of it at ``fullChroma``, so grays and
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
        guard node.chroma > HueBands.minimumChroma else { return node.rgb }

        var shift = SIMD3<Double>.zero
        for (index, bandShift) in shifts.enumerated() where bandShift != .zero {
            shift += HueBands.weight(hue: node.hue, center: HueBands.centers[index], width: widths[index]) * bandShift
        }
        shift *= HueBands.chromaGate(node.chroma, full: Self.fullChroma)

        guard shift != .zero else { return node.rgb }

        var lightness = node.oklab.x
        var chroma = simd_length(SIMD2(node.oklab.y, node.oklab.z))
        let hue = node.hue + shift.x * Self.maximumHueShift

        // A turned color takes its share of the new hue's most colorful sRGB color, and part of the
        // way toward that color's lightness: yellow held at its own lightness has no orange to become.
        if shift.x != 0 {
            let from = ColorMath.sRGBCusp(hue: node.hue)
            let to = ColorMath.sRGBCusp(hue: hue)
            let share = chroma / from.y
            lightness += Self.hueLightnessShare * share * (to.x - from.x)
            chroma = share * to.y
        }

        chroma *= max(0, 1 + shift.y)
        lightness += shift.z * node.chroma * (shift.z > 0 ? Self.maximumLightening : Self.maximumDarkening)

        return ColorMath.sRGB(lightness: lightness, chroma: chroma, hue: hue)
    }

    // MARK: - Mapping from slider positions

    /// Oklch degrees a full hue shift turns its band.
    static let maximumHueShift: Double = 60
    /// How much of the lightness difference between its old and new hues' sRGB cusps a turned color
    /// takes on. Moving all of it keeps the most chroma; none keeps lightness and can leave none.
    static let hueLightnessShare: Double = 0.5
    /// Oklab lightness a full negative luminance shift takes from a fully colorful pixel.
    static let maximumDarkening: Double = 0.35
    /// Oklab lightness a full positive luminance shift adds to a fully colorful pixel.
    static let maximumLightening: Double = 0.12
    /// The chroma, max − min of sRGB-encoded channels, at which a pixel takes its band's whole shift.
    static let fullChroma: Double = 0.25
}
