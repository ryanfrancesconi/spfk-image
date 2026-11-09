// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation

extension ImageAdjustmentRenderer {
    typealias SelectiveColor = ImageAdjustmentDescription.SelectiveColor

    static func selectiveColor(_ image: CIImage, _ adjustments: ImageAdjustmentDescription) -> CIImage {
        let values = ImageAdjustmentDescription.Parameter.selectiveColor.map { adjustments[$0] }
        let shifts = SelectiveColor.allCases.map { band in
            SIMD3(adjustments[band.hue], adjustments[band.saturation], adjustments[band.luminance])
        }

        return colorCube(image, step: "selectiveColor", values: values) { selectiveColor($0, shifts: shifts) }
    }

    /// `rgb` with each band's hue, saturation and luminance shift, in ``SelectiveColor`` order, weighed by
    /// how close the pixel's hue is to the band's center: fully at the center, falling linearly to
    /// nothing at the neighboring band's. The shift also scales with chroma, from none at
    /// ``selectiveColorMinimumChroma`` to all of it at ``selectiveColorFullChroma``, so grays and
    /// near-grays, whose hue is noise, do not move.
    static func selectiveColor(_ rgb: SIMD3<Double>, shifts: [SIMD3<Double>]) -> SIMD3<Double> {
        let chroma = rgb.max() - rgb.min()
        guard chroma > selectiveColorMinimumChroma else { return rgb }

        var (hue, saturation, lightness) = hsl(rgb)
        var shift = SIMD3<Double>.zero

        for (band, bandShift) in zip(SelectiveColor.allCases, shifts) {
            shift += bandWeight(hue: hue, band) * bandShift
        }

        shift *= chromaGate(chroma, full: selectiveColorFullChroma)

        hue += shift.x * maximumSelectiveHueShift
        saturation = min(1, saturation * (1 + shift.y))
        lightness += shift.z * maximumSelectiveLuminanceShift * (shift.z > 0 ? 1 - lightness : lightness)

        return Self.rgb(hue: hue, saturation: saturation, lightness: lightness)
    }

    /// How much a pixel of `hue` belongs to `band`: 1 at the band's center, falling linearly to 0 at
    /// the neighboring band's.
    static func bandWeight(hue: Double, _ band: SelectiveColor) -> Double {
        max(0, 1 - abs(remainder(hue - band.centerHue, 360)) / 60)
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

    /// Degrees a full hue shift turns its band.
    static let maximumSelectiveHueShift: Double = 30
    /// The share of the way to white or black a full luminance shift moves its band.
    static let maximumSelectiveLuminanceShift: Double = 0.5
    /// The chroma, max − min of sRGB-encoded channels, at which a pixel takes its band's whole shift.
    static let selectiveColorFullChroma: Double = 0.25
    /// The chroma at or below which a pixel takes none. Above one step of the color cube, so a gray's
    /// lookup, which blends the nodes around it, blends only unshifted ones.
    static let selectiveColorMinimumChroma: Double = 0.05
}
