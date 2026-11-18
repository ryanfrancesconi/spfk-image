// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import simd
@testable import SPFKImage
import Testing

@Suite("Oklab")
struct ImageAdjustmentOklabTests {
    typealias Renderer = ImageAdjustmentRenderer

    private func oklch(_ rgb: SIMD3<Double>) -> (lightness: Double, chroma: Double, hue: Double) {
        let lab = Renderer.oklab(rgb)
        return (lab.x, simd_length(SIMD2(lab.y, lab.z)), Renderer.oklchHue(lab))
    }

    @Test func aGridRoundTrips() {
        var worst = 0.0

        for red in stride(from: 0.0, through: 1, by: 0.1) {
            for green in stride(from: 0.0, through: 1, by: 0.1) {
                for blue in stride(from: 0.0, through: 1, by: 0.1) {
                    let color = SIMD3(red, green, blue)
                    let lch = oklch(color)
                    let back = Renderer.sRGB(lightness: lch.lightness, chroma: lch.chroma, hue: lch.hue)
                    worst = max(worst, simd_reduce_max(simd_abs(back - color)))
                }
            }
        }

        #expect(worst < 1e-5)
    }

    @Test(arguments: [
        (SIMD3(1.0, 0, 0), 29.0), (SIMD3(1.0, 1, 0), 110), (SIMD3(0.0, 1, 0), 142),
        (SIMD3(0.0, 1, 1), 195), (SIMD3(0.0, 0, 1), 264), (SIMD3(1.0, 0, 1), 328),
    ])
    func primariesAndSecondariesHaveTheirOklchHues(color: SIMD3<Double>, hue: Double) {
        #expect(abs(oklch(color).hue - hue) < 1, "\(color): \(oklch(color).hue)")
    }

    @Test(arguments: [
        SIMD3(1.0, 0, 0), SIMD3(1.0, 1, 0), SIMD3(0.0, 1, 0), SIMD3(0.0, 1, 1), SIMD3(0.0, 0, 1), SIMD3(1.0, 0, 1),
    ])
    func aPrimarysCuspIsThePrimary(color: SIMD3<Double>) {
        let lch = oklch(color)
        let cusp = Renderer.sRGBCusp(hue: lch.hue)

        #expect(abs(cusp.x - lch.lightness) < 0.002, "\(cusp)")
        #expect(abs(cusp.y - lch.chroma) < 0.002, "\(cusp)")
    }

    /// Just below blue's hue the most colorful sRGB color is a cyan-leaning blue: the cusps' hue
    /// folds back at blue, so the cusp jumps there.
    @Test func theCuspJumpsAtBlue() {
        let blue = oklch(SIMD3(0, 0, 1))
        let below = Renderer.sRGBCusp(hue: blue.hue - 0.1)

        #expect(blue.chroma - below.y > 0.01, "\(below)")
    }

    @Test func cuspsAreContinuousAwayFromBlue() {
        for hue in stride(from: 0.0, to: 360, by: 0.05) where abs(hue - oklch(SIMD3(0, 0, 1)).hue) > 0.2 {
            let step = Renderer.sRGBCusp(hue: hue + 0.05) - Renderer.sRGBCusp(hue: hue)
            #expect(abs(step.x) < 0.003 && abs(step.y) < 0.003, "at \(hue): \(step)")
        }
    }

    /// A chroma beyond sRGB comes back at the gamut's edge with its lightness and hue, not with a
    /// channel clipped, which would turn its hue.
    @Test func anOutOfGamutChromaKeepsLightnessAndHue() {
        for hue in stride(from: 0.0, to: 360, by: 15) {
            for lightness in [0.3, 0.5, 0.7, 0.9] {
                let fitted = Renderer.sRGB(lightness: lightness, chroma: 0.5, hue: hue)
                let lch = oklch(fitted)

                #expect(fitted.min() >= 0 && fitted.max() <= 1)
                #expect(abs(lch.lightness - lightness) < 0.005, "L \(lightness) h \(hue): \(lch.lightness)")
                #expect(abs(remainder(lch.hue - hue, 360)) < 1, "L \(lightness) h \(hue): \(lch.hue)")
                let atEdge = Renderer.sRGBDecoded(fitted.min()) < 0.001 || Renderer.sRGBDecoded(fitted.max()) > 0.999
                #expect(atEdge, "L \(lightness) h \(hue) stopped inside the gamut: \(fitted)")
            }
        }
    }
}
