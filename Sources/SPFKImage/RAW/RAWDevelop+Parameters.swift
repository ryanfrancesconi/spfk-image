// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension RAWDevelop {
    /// The renderer's steps the develop takes over. They must stay the first steps of `RenderStep`, so
    /// everything left in ``Parameters/remaining`` runs after the develop in the renderer's own order.
    static let developSteps: [RenderStep] = [.noiseReduction, .exposure, .whiteBalance]

    /// The lowest and highest white the Temperature slider can name, in mired: 50,000 K and 2,000 K.
    static let minimumMired: Double = 20
    static let maximumMired: Double = 500

    /// `CIRAWFilter`'s tint per unit of CIE 1960 (u, v), Adobe's scale, so full Tint is +150 and -129.
    static let tintPerUVOffset: Double = 3000

    /// Whether the develop takes any of `adjustments`' effective values, so developing with them
    /// differs from the default develop. Noise Reduction counts, whether or not a given file supports it.
    public static func takesAny(of adjustments: ImageAdjustmentDescription) -> Bool {
        Parameters(adjustments, asShotTemperature: 5000, asShotTint: 0, supportsLuminanceNoiseReduction: true).remaining
            != adjustments.effective
    }

    /// Temperature and Tint, in slider units, that develop to the neutral pair against the as-shot
    /// pair: the inverse of ``Parameters``' white balance, each limited to its parameter's range.
    static func whiteBalance(
        neutralTemperature: Double,
        neutralTint: Double,
        asShotTemperature: Double,
        asShotTint: Double
    ) -> (temperature: Double, tint: Double) {
        let temperature = (1_000_000 / asShotTemperature - 1_000_000 / neutralTemperature) / WhiteBalanceStep.miredPerUnit

        let difference = neutralTint - asShotTint
        let offset = difference > 0 ? WhiteBalanceStep.maximumMagentaTintOffset : WhiteBalanceStep.maximumGreenTintOffset
        let tint = difference / (offset * tintPerUVOffset)

        return (
            ImageAdjustmentDescription.Parameter.temperature.sanitize(temperature),
            ImageAdjustmentDescription.Parameter.tint.sanitize(tint)
        )
    }

    /// The filter's values for one description, and what is left for the renderer.
    struct Parameters: Equatable {
        /// Stops; 0 leaves the filter's default.
        var exposure: Double
        /// Kelvin; nil leaves the as-shot value.
        var neutralTemperature: Double?
        /// nil leaves the as-shot value.
        var neutralTint: Double?
        /// nil leaves the filter's default.
        var luminanceNoiseReduction: Double?
        /// The effective description with each value the develop takes returned to 0.
        var remaining: ImageAdjustmentDescription

        init(
            _ adjustments: ImageAdjustmentDescription,
            asShotTemperature: Double,
            asShotTint: Double,
            supportsLuminanceNoiseReduction: Bool
        ) {
            var remaining = adjustments.effective

            exposure = remaining.light.exposure
            remaining.light.exposure = 0

            let temperature = remaining.color.temperature
            let tint = remaining.color.tint

            if temperature != 0 || tint != 0 {
                if temperature != 0 {
                    let mired = 1_000_000 / asShotTemperature - temperature * WhiteBalanceStep.miredPerUnit
                    neutralTemperature = 1_000_000 / min(max(mired, minimumMired), maximumMired)
                } else {
                    neutralTemperature = asShotTemperature
                }

                let offset = tint > 0 ? WhiteBalanceStep.maximumMagentaTintOffset : WhiteBalanceStep.maximumGreenTintOffset
                neutralTint = asShotTint + tint * offset * tintPerUVOffset

                remaining.color.temperature = 0
                remaining.color.tint = 0
            } else {
                neutralTemperature = nil
                neutralTint = nil
            }

            if supportsLuminanceNoiseReduction, remaining.detail.noiseReduction != 0 {
                luminanceNoiseReduction = remaining.detail.noiseReduction
                remaining.detail.noiseReduction = 0
            } else {
                luminanceNoiseReduction = nil
            }

            self.remaining = remaining
        }
    }
}
