// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension RAWDevelop {
    /// The renderer's steps the develop takes over. They must stay the first steps of `RenderStep`, so
    /// everything left in ``Parameters/remaining`` runs after the develop in the renderer's own order.
    static let developSteps: [RenderStep] = [.noiseReduction, .exposure, .whiteBalance]

    /// Groups no render step reads, taken only by the develop.
    public static let developGroups: [ImageAdjustmentDescription.Group] = [.raw]

    /// The lowest and highest white the Temperature slider can name, in mired: 50,000 K and 2,000 K.
    static let minimumMired: Double = 20
    static let maximumMired: Double = 500

    /// `CIRAWFilter`'s tint per unit of CIE 1960 (u, v), Adobe's scale, so full Tint is +150 and -129.
    static let tintPerUVOffset: Double = 3000

    /// Whether the develop takes any of `adjustments`' effective values, so developing with them
    /// differs from the default develop. Noise Reduction and the RAW section count, whether or not a
    /// given file supports them.
    public static func takesAny(of adjustments: ImageAdjustmentDescription) -> Bool {
        let file = FileValues(
            asShotTemperature: 5000, asShotTint: 0, colorNoiseReduction: 0.5, moireReduction: 0.5, lensCorrection: true,
            supportsLuminanceNoiseReduction: true, supportsColorNoiseReduction: true, supportsMoireReduction: true,
            supportsLensCorrection: true
        )
        return Parameters(adjustments, file: file).remaining != adjustments.effective
    }

    /// What one file's develop starts from, read before any develop.
    struct FileValues: Equatable {
        var asShotTemperature: Double
        var asShotTint: Double
        /// The filter's own amounts, 0...1.
        var colorNoiseReduction: Double
        var moireReduction: Double
        var lensCorrection: Bool
        var supportsLuminanceNoiseReduction: Bool
        var supportsColorNoiseReduction: Bool
        var supportsMoireReduction: Bool
        var supportsLensCorrection: Bool
    }

    /// The filter amount for `value`, a RAW section position relative to `fileDefault`: 0 is the
    /// default, -1 is 0 and 1 is 1.
    static func amount(_ value: Double, relativeTo fileDefault: Double) -> Double {
        value >= 0 ? fileDefault + value * (1 - fileDefault) : fileDefault * (1 + value)
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
        /// Filter amounts; nil leaves the file's default.
        var colorNoiseReduction: Double?
        var moireReduction: Double?
        /// nil leaves the file's default.
        var lensCorrection: Bool?
        /// The effective description with each value the develop takes returned to 0.
        var remaining: ImageAdjustmentDescription

        init(_ adjustments: ImageAdjustmentDescription, file: FileValues) {
            let asShotTemperature = file.asShotTemperature
            let asShotTint = file.asShotTint
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

            if file.supportsLuminanceNoiseReduction, remaining.detail.noiseReduction != 0 {
                luminanceNoiseReduction = remaining.detail.noiseReduction
                remaining.detail.noiseReduction = 0
            } else {
                luminanceNoiseReduction = nil
            }

            let raw = remaining.raw
            colorNoiseReduction = file.supportsColorNoiseReduction && raw.colorNoiseReduction != 0
                ? RAWDevelop.amount(raw.colorNoiseReduction, relativeTo: file.colorNoiseReduction) : nil
            moireReduction = file.supportsMoireReduction && raw.moireReduction != 0
                ? RAWDevelop.amount(raw.moireReduction, relativeTo: file.moireReduction) : nil
            lensCorrection = file.supportsLensCorrection && raw.lensCorrection != 0 ? raw.lensCorrection > 0 : nil
            remaining.raw = ImageAdjustmentDescription.RAW()

            self.remaining = remaining
        }
    }
}
