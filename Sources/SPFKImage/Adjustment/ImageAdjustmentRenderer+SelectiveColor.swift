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
        let widths = ColorBand.allCases.map { bandWidth(range: selectiveColor[$0].range) }
        let values = shifts.flatMap { [$0.x, $0.y, $0.z] } + widths

        return colorCube(image, step: "selectiveColor", values: values, nodeTransform: { Self.selectiveColor($0, shifts: shifts, widths: widths) })
    }

    static func selectiveColor(_ rgb: SIMD3<Double>, shifts: [SIMD3<Double>], widths: [Double]? = nil) -> SIMD3<Double> {
        selectiveColor(ColorCubeNode(rgb), shifts: shifts, widths: widths)
    }

    /// `node`'s color with each band's hue, saturation and luminance shift, in ``ColorBand`` order,
    /// weighed by ``bandWeight(hue:center:width:)`` at that band's entry in `widths`, or
    /// ``selectiveColorBandWidth`` when it is nil. The shift also scales with chroma, from none at
    /// ``selectiveColorMinimumChroma`` to all of it at ``selectiveColorFullChroma``, so grays and
    /// near-grays, whose hue is noise, do not move. Luminance scales with chroma again, so a dull
    /// color moves less than a vivid one.
    static func selectiveColor(_ node: ColorCubeNode, shifts: [SIMD3<Double>], widths: [Double]? = nil) -> SIMD3<Double> {
        guard node.chroma > selectiveColorMinimumChroma else { return node.rgb }

        var shift = SIMD3<Double>.zero
        for (index, bandShift) in shifts.enumerated() where bandShift != .zero {
            let width = widths?[index] ?? selectiveColorBandWidth
            shift += bandWeight(hue: node.hue, center: bandCenters[index], width: width) * bandShift
        }
        shift *= chromaGate(node.chroma, full: selectiveColorFullChroma)

        guard shift != .zero else { return node.rgb }

        var lightness = node.oklab.x
        var chroma = simd_length(SIMD2(node.oklab.y, node.oklab.z))
        let hue = node.hue + shift.x * maximumSelectiveHueShift

        // A turned color takes its share of the new hue's most colorful sRGB color, and part of the
        // way toward that color's lightness: yellow held at its own lightness has no orange to become.
        if shift.x != 0 {
            let from = sRGBCusp(hue: node.hue)
            let to = sRGBCusp(hue: hue)
            let share = chroma / from.y
            lightness += selectiveHueLightnessShare * share * (to.x - from.x)
            chroma = share * to.y
        }

        chroma *= max(0, 1 + shift.y)
        lightness += shift.z * node.chroma * (shift.z > 0 ? maximumSelectiveLightening : maximumSelectiveDarkening)

        return sRGB(lightness: lightness, chroma: chroma, hue: hue)
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
        let reference = bandReference(band)
        let range = band.parameter(component).range
        let count = max(2, stops)

        return (0 ..< count).map { stop in
            var swept = shift
            swept[component] = range.lowerBound + (range.upperBound - range.lowerBound) * Double(stop) / Double(count - 1)

            let shifts = ColorBand.allCases.map { $0 == band ? SIMD3(swept.hue, swept.saturation, swept.luminance) : .zero }
            return selectiveColor(reference, shifts: shifts)
        }
    }

    /// How much a pixel of Oklch `hue` belongs to the band centered on `center`: 1 at the center,
    /// smoothstepping to 0 at `width` degrees away. Neighboring bands overlap, so their shifts add.
    static func bandWeight(hue: Double, center: Double, width: Double = selectiveColorBandWidth) -> Double {
        let distance = hue - center
        let ramp = max(0, 1 - abs(distance - 360 * (distance / 360).rounded()) / width)
        return ramp * ramp * (3 - 2 * ramp)
    }

    /// ``selectiveColorBandWidth`` scaled by `2^range`: half as wide at −1, twice as wide at 1.
    static func bandWidth(range: Double) -> Double {
        selectiveColorBandWidth * pow(2, range)
    }

    /// The color a band's tracks start from: its HSL center at ``bandTrackSaturation`` and lightness
    /// 0.5, turned onto the band's Oklch center so that the band's whole shift applies to it.
    static func bandReference(_ band: ColorBand) -> SIMD3<Double> {
        let lab = oklab(rgb(hue: band.centerHue, saturation: bandTrackSaturation, lightness: 0.5))
        return sRGB(lightness: lab.x, chroma: simd_length(SIMD2(lab.y, lab.z)), hue: bandCenter(band))
    }

    static func bandCenter(_ band: ColorBand) -> Double {
        bandCenters[ColorBand.allCases.firstIndex(of: band) ?? 0]
    }

    /// Each band's center in ``ColorBand`` order: the Oklch hue of its sRGB primary or secondary.
    static let bandCenters: [Double] = ColorBand.allCases.map { band in
        oklchHue(oklab(rgb(hue: band.centerHue, saturation: 1, lightness: 0.5)))
    }

    /// 0 at or below ``selectiveColorMinimumChroma``, smoothstepping to 1 at `full`.
    static func chromaGate(_ chroma: Double, full: Double) -> Double {
        let ramp = min(1, max(0, (chroma - selectiveColorMinimumChroma) / (full - selectiveColorMinimumChroma)))
        return ramp * ramp * (3 - 2 * ramp)
    }

    /// Hue in degrees, 0…360; saturation and lightness in 0…1.
    static func hsl(_ rgb: SIMD3<Double>) -> (hue: Double, saturation: Double, lightness: Double) {
        let high = rgb.max()
        let low = rgb.min()
        let chroma = high - low
        let lightness = (high + low) / 2

        guard chroma > 0 else { return (0, 0, lightness) }

        let saturation = chroma / (1 - abs(2 * lightness - 1))

        var hue: Double
        if high == rgb.x {
            hue = ((rgb.y - rgb.z) / chroma).truncatingRemainder(dividingBy: 6)
        } else if high == rgb.y {
            hue = (rgb.z - rgb.x) / chroma + 2
        } else {
            hue = (rgb.x - rgb.y) / chroma + 4
        }

        hue *= 60
        if hue < 0 { hue += 360 }

        return (hue, min(1, saturation), lightness)
    }

    static func rgb(hue: Double, saturation: Double, lightness: Double) -> SIMD3<Double> {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))

        let base: SIMD3<Double> = switch Int(sector) {
        case 0: SIMD3(chroma, second, 0)
        case 1: SIMD3(second, chroma, 0)
        case 2: SIMD3(0, chroma, second)
        case 3: SIMD3(0, second, chroma)
        case 4: SIMD3(second, 0, chroma)
        default: SIMD3(chroma, 0, second)
        }

        return base + SIMD3(repeating: lightness - chroma / 2)
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
    /// Oklch degrees from a band's center at which its weight reaches 0, at Range 0.
    static let selectiveColorBandWidth: Double = 75
    /// The chroma, max − min of sRGB-encoded channels, at which a pixel takes its band's whole shift.
    static let selectiveColorFullChroma: Double = 0.25
    /// The HSL saturation of a band's track reference color: colorful enough at lightness 0.5 for
    /// Black & White's whole shift, with room left in sRGB for Selective Color's saturation to rise.
    static let bandTrackSaturation: Double = 0.5
    /// The chroma at or below which a pixel takes none. Above one step of the color cube, so a gray's
    /// lookup, which blends the nodes around it, blends only unshifted ones.
    static let selectiveColorMinimumChroma: Double = 0.05
}
