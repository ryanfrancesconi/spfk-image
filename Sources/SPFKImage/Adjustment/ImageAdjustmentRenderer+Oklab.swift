// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import simd

/// Oklab conversions, from Björn Ottosson, "A perceptual color space for image processing" (2020).
extension ImageAdjustmentRenderer {
    /// Oklab lightness, a and b of sRGB-encoded `rgb`.
    static func oklab(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let linear = SIMD3(sRGBDecoded(rgb.x), sRGBDecoded(rgb.y), sRGBDecoded(rgb.z))
        let l = cbrt(0.4122214708 * linear.x + 0.5363325363 * linear.y + 0.0514459929 * linear.z)
        let m = cbrt(0.2119034982 * linear.x + 0.6806995451 * linear.y + 0.1073969566 * linear.z)
        let s = cbrt(0.0883024619 * linear.x + 0.2817188376 * linear.y + 0.6299787005 * linear.z)

        return SIMD3(
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    /// Oklch hue of `oklab`, in degrees, 0…360.
    static func oklchHue(_ oklab: SIMD3<Double>) -> Double {
        let hue = atan2(oklab.z, oklab.y) * 180 / .pi
        return hue < 0 ? hue + 360 : hue
    }

    /// Linear sRGB of `oklab`, unclamped.
    static func linearSRGB(oklab: SIMD3<Double>) -> SIMD3<Double> {
        linearSRGB(lmsRoot: lmsRoot(oklab))
    }

    /// The cube roots of LMS that `oklab` is a linear map of.
    private static func lmsRoot(_ oklab: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            oklab.x + 0.3963377774 * oklab.y + 0.2158037573 * oklab.z,
            oklab.x - 0.1055613458 * oklab.y - 0.0638541728 * oklab.z,
            oklab.x - 0.0894841775 * oklab.y - 1.2914855480 * oklab.z
        )
    }

    private static func linearSRGB(lmsRoot: SIMD3<Double>) -> SIMD3<Double> {
        let lms = lmsRoot * lmsRoot * lmsRoot

        return SIMD3(
            4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z,
            -1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z,
            -0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z
        )
    }

    /// The sRGB-encoded color at Oklch `lightness`, `chroma` and `hue` (degrees). Lightness is clamped
    /// to 0…1; a color outside sRGB has its chroma reduced until it fits, keeping lightness and hue.
    ///
    /// `insideChroma`, a chroma known to fit at this lightness and hue, is the least the reduction
    /// returns. Near blue the colors that fit along a hue are not one interval from gray, so a search
    /// from 0 can stop short of a color already inside.
    static func sRGB(lightness: Double, chroma: Double, hue: Double, insideChroma: Double = 0) -> SIMD3<Double> {
        let lightness = min(1, max(0, lightness))
        let chroma = max(0, chroma)
        let radians = hue * .pi / 180
        let base = lmsRoot(SIMD3(lightness, 0, 0))
        let direction = lmsRoot(SIMD3(0, cos(radians), sin(radians)))

        var linear = linearSRGB(lmsRoot: base + chroma * direction)

        if gamutExcess(linear) > 0 {
            let inside = min(max(0, insideChroma), chroma)
            var low = (chroma: inside, linear: linearSRGB(lmsRoot: base + inside * direction))
            var high = (chroma: chroma, linear: linear)

            for _ in 0 ..< gamutSearchSteps {
                let middle = (low.chroma + high.chroma) / 2
                let candidate = (chroma: middle, linear: linearSRGB(lmsRoot: base + middle * direction))
                if gamutExcess(candidate.linear) > 0 { high = candidate } else { low = candidate }
            }

            // The edge lies where the slack inside meets the excess outside.
            let slack = -gamutExcess(low.linear)
            let fraction = slack / (slack + gamutExcess(high.linear))
            linear = linearSRGB(lmsRoot: base + (low.chroma + (high.chroma - low.chroma) * fraction) * direction)
        }

        let clamped = simd_clamp(linear, SIMD3(repeating: 0), SIMD3(repeating: 1))
        return SIMD3(sRGBEncoded(clamped.x), sRGBEncoded(clamped.y), sRGBEncoded(clamped.z))
    }

    /// How far the furthest channel of `linear` lies outside 0…1, beyond a tolerance for the
    /// conversions' rounding; negative inside, by the nearest channel's margin.
    private static func gamutExcess(_ linear: SIMD3<Double>) -> Double {
        max(-linear.min(), linear.max() - 1) - 1e-6
    }

    /// Bisection steps fitting a chroma into sRGB, before a final interpolation.
    private static let gamutSearchSteps = 8

    // MARK: - sRGB cusps

    /// Oklch lightness and chroma of the most colorful sRGB color at `hue` (degrees).
    static func sRGBCusp(hue: Double) -> SIMD2<Double> {
        sRGBCusps[cuspSlot(hue)]
    }

    private static let cuspSlotsPerDegree = 20

    private static func cuspSlot(_ hue: Double) -> Int {
        let slots = 360 * cuspSlotsPerDegree
        return (Int((hue * Double(cuspSlotsPerDegree)).rounded(.down)) % slots + slots) % slots
    }

    /// The most colorful of the fully saturated colors, the cube's edges between primaries and
    /// secondaries, whose Oklch hue falls in each slot. That hue folds back at blue, so the cusp jumps
    /// there, which is why slots are read whole rather than interpolated.
    private static let sRGBCusps: [SIMD2<Double>] = {
        let samples: [(hue: Double, cusp: SIMD2<Double>)] = (0 ..< 14400).map { step in
            let lab = oklab(rgb(hue: Double(step) / 40, saturation: 1, lightness: 0.5))
            return (oklchHue(lab), SIMD2(lab.x, simd_length(SIMD2(lab.y, lab.z))))
        }

        var cusps = [SIMD2<Double>](repeating: .zero, count: 360 * cuspSlotsPerDegree)

        func keep(_ cusp: SIMD2<Double>, in slot: Int) {
            if cusp.y > cusps[slot].y { cusps[slot] = cusp }
        }

        for (index, start) in samples.enumerated() {
            keep(start.cusp, in: cuspSlot(start.hue))

            // Slots crossed between this sample and the next take the edge at their boundary.
            let end = samples[(index + 1) % samples.count]
            let span = remainder(end.hue - start.hue, 360)
            guard span != 0 else { continue }

            let scale = Double(cuspSlotsPerDegree)
            let low = min(start.hue, start.hue + span) * scale
            for boundary in stride(from: Int(low.rounded(.up)), through: Int((low + abs(span) * scale).rounded(.down)), by: 1) {
                let fraction = (Double(boundary) / scale - start.hue) / span
                let cusp = start.cusp + (end.cusp - start.cusp) * fraction
                keep(cusp, in: cuspSlot(Double(boundary) / scale))
                keep(cusp, in: cuspSlot(Double(boundary - 1) / scale))
            }
        }

        return cusps
    }()
}
