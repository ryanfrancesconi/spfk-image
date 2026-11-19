// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum HighlightsShadowsStep {
    /// Negative values through `CIHighlightShadowAdjust`; positive Highlights through a tone curve,
    /// then positive Shadows through ``ShadowsTransform``.
    static func apply(_ image: CIImage, highlights: Double, shadows: Double) -> CIImage {
        var output = image

        if highlights < 0 || shadows < 0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = output
            filter.highlightAmount = Float(highlightAmount(highlights))
            filter.shadowAmount = Float(min(shadows, 0))
            output = filter.outputImage ?? output
        }

        if highlights > 0 {
            output = ToneCurve.apply(output, highlightsCurve(highlights))
        }

        if shadows > 0 {
            output = ColorCube.apply(ShadowsTransform(shadows), to: output)
        }

        return output
    }

    /// `CIHighlightShadowAdjust`'s highlight amount for negative Highlights, 1 (neutral) down to
    /// ``minimumHighlightAmount``.
    static func highlightAmount(_ value: Double) -> Double {
        1 + min(value, 0) * (1 - minimumHighlightAmount)
    }

    /// The Highlights value that renders as `CIHighlightShadowAdjust` at highlight `amount`; the
    /// inverse of ``highlightAmount(_:)``.
    static func highlights(forHighlightAmount amount: Double) -> Double {
        (amount - 1) / (1 - minimumHighlightAmount)
    }

    /// Lifts the upper tones by ``highlightsLift``, so black and white stay fixed.
    static func highlightsCurve(_ value: Double) -> [CGPoint] {
        ToneCurve.lifted(by: highlightsLift, value)
    }

    /// The Shadows value that renders `CIHighlightShadowAdjust`'s shadow `amount` at about the same
    /// lift of a quarter gray. Negative amounts render through the filter unchanged.
    static func shadows(forShadowAmount amount: Double) -> Double {
        amount > 0 ? amount * shadowAmountToSlider : amount
    }

    // MARK: - Mapping from slider positions

    /// `CIHighlightShadowAdjust`'s highlight amount at full negative Highlights. Lower flattens the
    /// highlights into one tone.
    static let minimumHighlightAmount: Double = 0.25
    /// How far full positive Highlights moves each of `ToneCurve.positions`, in sRGB-encoded values.
    static let highlightsLift: [Double] = [0, 0, 0.02, 0.07, 0]
    /// Auto's positive shadow amounts (measured 0.05…0.33) on the Shadows slider. Within 0.03 of the
    /// filter's lift of a flat quarter gray up to amount 0.3; photos, where the filter lifts more, want
    /// between 1.3 and 2.
    static let shadowAmountToSlider: Double = 1.5
}
