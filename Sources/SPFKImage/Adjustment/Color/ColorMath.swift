// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import simd

/// Color conversions on single colors, with no Core Image in them: the sRGB transfer curve, HSL, the
/// sRGB and Display P3 primaries, and Oklab (`ColorMath+Oklab.swift`).
enum ColorMath {
    /// Rec. 709 luminance of linear red, green and blue.
    static let luminanceWeights = SIMD3<Double>(0.2126, 0.7152, 0.0722)

    static func sRGBDecoded(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    static func sRGBEncoded(_ value: Double) -> Double {
        value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    /// The color at HSL `hue` in degrees, `saturation` and `lightness` in 0…1.
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

    /// Linear Display P3 of linear sRGB, as ColorSync converts between `extendedLinearSRGB` and
    /// `extendedLinearDisplayP3`. Display P3 shares sRGB's transfer curve.
    static let linearSRGBToDisplayP3 = simd_double3x3(rows: [
        SIMD3(0.8224260807, 0.1775570065, 0.0000168917),
        SIMD3(0.0332198292, 0.9667982459, -0.0000180696),
        SIMD3(0.0170741770, 0.0723747835, 0.9105510712),
    ])

    static let displayP3ToLinearSRGB = linearSRGBToDisplayP3.inverse
}
