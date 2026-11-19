// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import simd

extension ImageAdjustmentRenderer {
    typealias ColorBand = ImageAdjustmentDescription.ColorBand

    static func selectiveColor(_ image: CIImage, _ selectiveColor: ImageAdjustmentDescription.SelectiveColor) -> CIImage {
        let shifts = ColorBand.allCases.map { band in
            SIMD3(selectiveColor[band].hue, selectiveColor[band].saturation, selectiveColor[band].luminance)
        }
        let widths = ColorBand.allCases.map { HueBands.width(range: selectiveColor[$0].range) }
        let values = shifts.flatMap { [$0.x, $0.y, $0.z] } + widths

        return colorCube(image, step: "selectiveColor", values: values, nodeTransform: { Self.selectiveColor($0, shifts: shifts, widths: widths) })
    }

    static func selectiveColor(_ rgb: SIMD3<Double>, shifts: [SIMD3<Double>], widths: [Double]? = nil) -> SIMD3<Double> {
        selectiveColor(ColorCubeNode(rgb), shifts: shifts, widths: widths)
    }

    /// `node`'s color with each band's hue, saturation and luminance shift, in ``ColorBand`` order,
    /// weighed by ``HueBands/weight(hue:center:width:)`` at that band's entry in `widths`, or
    /// ``HueBands/defaultWidth`` when it is nil. The shift also scales with chroma, from none at
    /// ``HueBands/minimumChroma`` to all of it at ``selectiveColorFullChroma``, so grays and
    /// near-grays, whose hue is noise, do not move. Luminance scales with chroma again, so a dull
    /// color moves less than a vivid one.
    static func selectiveColor(_ node: ColorCubeNode, shifts: [SIMD3<Double>], widths: [Double]? = nil) -> SIMD3<Double> {
        guard node.chroma > HueBands.minimumChroma else { return node.rgb }

        var shift = SIMD3<Double>.zero
        for (index, bandShift) in shifts.enumerated() where bandShift != .zero {
            let width = widths?[index] ?? HueBands.defaultWidth
            shift += HueBands.weight(hue: node.hue, center: HueBands.centers[index], width: width) * bandShift
        }
        shift *= HueBands.chromaGate(node.chroma, full: selectiveColorFullChroma)

        guard shift != .zero else { return node.rgb }

        var lightness = node.oklab.x
        var chroma = simd_length(SIMD2(node.oklab.y, node.oklab.z))
        let hue = node.hue + shift.x * maximumSelectiveHueShift

        // A turned color takes its share of the new hue's most colorful sRGB color, and part of the
        // way toward that color's lightness: yellow held at its own lightness has no orange to become.
        if shift.x != 0 {
            let from = ColorMath.sRGBCusp(hue: node.hue)
            let to = ColorMath.sRGBCusp(hue: hue)
            let share = chroma / from.y
            lightness += selectiveHueLightnessShare * share * (to.x - from.x)
            chroma = share * to.y
        }

        chroma *= max(0, 1 + shift.y)
        lightness += shift.z * node.chroma * (shift.z > 0 ? maximumSelectiveLightening : maximumSelectiveDarkening)

        return ColorMath.sRGB(lightness: lightness, chroma: chroma, hue: hue)
    }

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
            return selectiveColor(reference, shifts: shifts)
        }
    }

    // MARK: - Mapping from slider positions

    /// Oklch degrees a full hue shift turns its band.
    static let maximumSelectiveHueShift: Double = 60
    /// How much of the lightness difference between its old and new hues' sRGB cusps a turned color
    /// takes on. Moving all of it keeps the most chroma; none keeps lightness and can leave none.
    static let selectiveHueLightnessShare: Double = 0.5
    /// Oklab lightness a full negative luminance shift takes from a fully colorful pixel.
    static let maximumSelectiveDarkening: Double = 0.35
    /// Oklab lightness a full positive luminance shift adds to a fully colorful pixel.
    static let maximumSelectiveLightening: Double = 0.12
    /// The chroma, max − min of sRGB-encoded channels, at which a pixel takes its band's whole shift.
    static let selectiveColorFullChroma: Double = 0.25
}
