// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

extension ImageAdjustmentRenderer {
    /// Negative values through `CIHighlightShadowAdjust`; positive Highlights through a tone curve,
    /// then positive Shadows through ``liftShadows(_:_:)``.
    static func highlightsAndShadows(_ image: CIImage, highlights: Double, shadows: Double) -> CIImage {
        var output = image

        if highlights < 0 || shadows < 0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = output
            filter.highlightAmount = Float(highlightAmount(highlights))
            filter.shadowAmount = Float(min(shadows, 0))
            output = filter.outputImage ?? output
        }

        if highlights > 0 {
            output = toneCurve(output, highlightsCurve(highlights))
        }

        if shadows > 0 {
            output = liftShadows(output, shadows)
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
        zip(curvePositions, highlightsLift).map { x, lift in CGPoint(x: x, y: x + value * lift) }
    }

    /// The Shadows value that renders `CIHighlightShadowAdjust`'s shadow `amount` at about the same
    /// lift of a quarter gray. Negative amounts render through the filter unchanged.
    static func shadows(forShadowAmount amount: Double) -> Double {
        amount > 0 ? amount * shadowAmountToSlider : amount
    }

    /// Moves each pixel's brightest channel along ``shadowsCurve(_:)`` and scales the other two by the
    /// same ratio, so hue holds and no channel passes 1.
    static func liftShadows(_ image: CIImage, _ value: Double) -> CIImage {
        let curve = shadowsCurve(value)

        return colorCube(image, step: "shadows", values: [value]) { rgb in
            let peak = rgb.max()
            guard peak > 0 else { return rgb }
            return rgb * (curve.value(at: peak) / peak)
        }
    }

    /// Lifts the lower tones by ``shadowsLift``, so black and white stay fixed.
    static func shadowsCurve(_ value: Double) -> MonotoneCubicInterpolation {
        MonotoneCubicInterpolation(x: curvePositions, y: zip(curvePositions, shadowsLift).map { $0 + value * $1 })
    }
}
