// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import simd

/// The six Oklch hue bands that Selective Color and Black & White shift, and how much a pixel belongs
/// to each.
enum HueBands {
    typealias Band = ImageAdjustmentDescription.ColorBand

    /// Each band's center in ``ImageAdjustmentDescription/ColorBand`` order: the Oklch hue of its sRGB
    /// primary or secondary.
    static let centers: [Double] = Band.allCases.map { band in
        ColorMath.oklchHue(ColorMath.oklab(ColorMath.rgb(hue: band.centerHue, saturation: 1, lightness: 0.5)))
    }

    static func center(_ band: Band) -> Double {
        centers[Band.allCases.firstIndex(of: band) ?? 0]
    }

    /// How much a pixel of Oklch `hue` belongs to the band centered on `center`: 1 at the center,
    /// smoothstepping to 0 at `width` degrees away. Neighboring bands overlap, so their shifts add.
    static func weight(hue: Double, center: Double, width: Double = defaultWidth) -> Double {
        let distance = hue - center
        let ramp = max(0, 1 - abs(distance - 360 * (distance / 360).rounded()) / width)
        return ramp * ramp * (3 - 2 * ramp)
    }

    /// ``defaultWidth`` scaled by `2^range`: half as wide at −1, twice as wide at 1.
    static func width(range: Double) -> Double {
        defaultWidth * pow(2, range)
    }

    /// 0 at or below ``minimumChroma``, smoothstepping to 1 at `full`.
    static func chromaGate(_ chroma: Double, full: Double) -> Double {
        let ramp = min(1, max(0, (chroma - minimumChroma) / (full - minimumChroma)))
        return ramp * ramp * (3 - 2 * ramp)
    }

    /// The color a band's tracks start from: its HSL center at ``trackSaturation`` and lightness 0.5,
    /// turned onto the band's Oklch center so that the band's whole shift applies to it.
    static func reference(_ band: Band) -> SIMD3<Double> {
        let lab = ColorMath.oklab(ColorMath.rgb(hue: band.centerHue, saturation: trackSaturation, lightness: 0.5))
        return ColorMath.sRGB(lightness: lab.x, chroma: simd_length(SIMD2(lab.y, lab.z)), hue: center(band))
    }

    // MARK: - Constants

    /// Oklch degrees from a band's center at which its weight reaches 0, at Range 0.
    static let defaultWidth: Double = 75
    /// The chroma, max − min of sRGB-encoded channels, at or below which a pixel takes none. Above one
    /// step of the color cube, so a gray's lookup, which blends the nodes around it, blends only
    /// unshifted ones.
    static let minimumChroma: Double = 0.05
    /// The HSL saturation of a band's track reference color: colorful enough at lightness 0.5 for
    /// Black & White's whole shift, with room left in sRGB for Selective Color's saturation to rise.
    static let trackSaturation: Double = 0.5
}
