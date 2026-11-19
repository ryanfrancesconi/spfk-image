// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import simd

/// Temperature and Tint as a chromatic adaptation in linear sRGB: from a white point on or beside the
/// Planckian locus to the locus at ``neutralKelvin``.
extension ImageAdjustmentRenderer {
    /// The Temperature and Tint step. Does not clamp, so wide-gamut and HDR values pass through.
    static func temperatureAndTint(_ image: CIImage, temperature: Double, tint: Double) -> CIImage {
        CIArithmetic.matrix(image, whiteBalanceMatrix(temperature: temperature, tint: tint))
    }

    /// The linear sRGB matrix of the Temperature and Tint step, exactly identity at (0, 0).
    ///
    /// Bradford adaptation from the white the sliders name to the locus at ``neutralKelvin``, scaled to
    /// keep a neutral gray's Rec. 709 luminance.
    static func whiteBalanceMatrix(temperature: Double, tint: Double) -> simd_double3x3 {
        guard temperature != 0 || tint != 0 else { return matrix_identity_double3x3 }

        let kelvin = 1_000_000 / (1_000_000 / neutralKelvin - temperature * miredPerUnit)
        let offset = tint > 0 ? maximumMagentaTintOffset : maximumGreenTintOffset
        let source = planckianLocus(kelvin) + tint * offset * locusNormal(kelvin)

        let sourceCone = bradford * xyz(uv: source)
        let targetCone = bradford * xyz(uv: planckianLocus(neutralKelvin))
        let toCone = bradford * linearSRGBToXYZ
        let adaptation = toCone.inverse * simd_double3x3(diagonal: targetCone / sourceCone) * toCone

        return adaptation * (1 / simd_dot(ColorMath.luminanceWeights, adaptation * SIMD3(repeating: 1)))
    }

    /// CIE 1960 UCS (u, v) of a blackbody at `kelvin`, valid from 1000 to 15000 K. Krystek, "An
    /// algorithm to calculate correlated colour temperature", Color Res. Appl. 10(1), 1985.
    static func planckianLocus(_ kelvin: Double) -> SIMD2<Double> {
        let t = kelvin
        let u = (0.860117757 + 1.54118254e-4 * t + 1.28641212e-7 * t * t) / (1 + 8.42420235e-4 * t + 7.08145163e-7 * t * t)
        let v = (0.317398726 + 4.22806245e-5 * t + 4.20481691e-8 * t * t) / (1 - 2.89741816e-5 * t + 1.61456053e-7 * t * t)
        return SIMD2(u, v)
    }

    /// The unit normal to the locus at `kelvin` in (u, v), pointing to +v, the green side; the CIE's
    /// isotemperature lines run along it.
    static func locusNormal(_ kelvin: Double) -> SIMD2<Double> {
        let tangent = simd_normalize(planckianLocus(kelvin + 1) - planckianLocus(kelvin - 1))
        let normal = SIMD2(-tangent.y, tangent.x)
        return normal.y > 0 ? normal : -normal
    }

    /// CIE XYZ at Y = 1 of a CIE 1960 (u, v) chromaticity.
    static func xyz(uv: SIMD2<Double>) -> SIMD3<Double> {
        let denominator = 2 * uv.x - 8 * uv.y + 4
        let x = 3 * uv.x / denominator
        let y = 2 * uv.y / denominator
        return SIMD3(x / y, 1, (1 - x - y) / y)
    }

    /// IEC 61966-2-1. Its middle row is ``ColorMath/luminanceWeights``.
    static let linearSRGBToXYZ = simd_double3x3(rows: [
        SIMD3(0.4124, 0.3576, 0.1805),
        SIMD3(0.2126, 0.7152, 0.0722),
        SIMD3(0.0193, 0.1192, 0.9505),
    ])

    /// XYZ to Bradford cone responses, used with a linear von Kries scaling as ICC.1:2010 Annex E.3
    /// does. Fairchild, "Color Appearance Models", 2nd ed., 2005.
    static let bradford = simd_double3x3(rows: [
        SIMD3(0.8951, 0.2664, -0.1614),
        SIMD3(-0.7502, 1.7135, 0.0367),
        SIMD3(0.0389, -0.0685, 1.0296),
    ])
}
