// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import simd

extension ImageAdjustmentRenderer {
    /// The two values of the Temperature and Tint step.
    public enum WhiteBalanceComponent: CaseIterable, Sendable {
        case temperature
        case tint
    }

    /// The colors a mid gray takes as `component` moves across its slider range, with the other value
    /// as given, clamped to 0…1 as a display shows them. sRGB-encoded.
    public static func whiteBalanceTrack(
        component: WhiteBalanceComponent,
        temperature: Double,
        tint: Double,
        stops: Int = 25
    ) -> [SIMD3<Double>] {
        let range = component == .temperature
            ? ImageAdjustmentDescription.Parameter.temperature.range
            : ImageAdjustmentDescription.Parameter.tint.range
        let gray = SIMD3(repeating: ColorMath.sRGBDecoded(0.5))

        return sweep(range, stops: stops).map { value in
            let transform = component == .temperature
                ? WhiteBalanceStep.matrix(temperature: value, tint: tint)
                : WhiteBalanceStep.matrix(temperature: temperature, tint: value)
            let rgb = (transform * gray).clamped(lowerBound: .zero, upperBound: .one)
            return SIMD3(ColorMath.sRGBEncoded(rgb.x), ColorMath.sRGBEncoded(rgb.y), ColorMath.sRGBEncoded(rgb.z))
        }
    }

    /// The colors `band`'s reference color takes as `component` moves across its range, from minimum to
    /// maximum, with `shift`'s other components applied. sRGB-encoded, as the renderer works. Range
    /// does not change the reference, which sits on the band's center, so its track is one color.
    public static func selectiveColorTrack(
        _ band: ImageAdjustmentDescription.ColorBand,
        component: ImageAdjustmentDescription.SelectiveColor.Component,
        shift: ImageAdjustmentDescription.SelectiveColor.Shift,
        stops: Int = 25
    ) -> [SIMD3<Double>] {
        let reference = HueBands.reference(band)

        return sweep(band.parameter(component).range, stops: stops).map { value in
            var swept = shift
            swept[component] = value

            let shifts = ImageAdjustmentDescription.ColorBand.allCases.map {
                $0 == band ? SIMD3(swept.hue, swept.saturation, swept.luminance) : .zero
            }
            return SelectiveColorTransform(shifts: shifts)(reference)
        }
    }

    /// The grays `band`'s reference color becomes as its shift moves across its range, from minimum to
    /// maximum, with every other band at 0. sRGB-encoded.
    public static func blackAndWhiteTrack(_ band: ImageAdjustmentDescription.ColorBand, stops: Int = 25) -> [SIMD3<Double>] {
        let reference = HueBands.reference(band)

        return sweep(band.blackAndWhite.range, stops: stops).map { value in
            BlackAndWhiteTransform(shifts: ImageAdjustmentDescription.ColorBand.allCases.map { $0 == band ? value : 0 })(reference)
        }
    }

    /// The colors a mid gray takes as `component` moves across 0…1, its range, with `tint`'s other value
    /// applied. The Hue track is drawn at full saturation whatever `tint` holds, since hue alone renders
    /// nothing. sRGB-encoded, as the renderer works.
    public static func colorGradingTrack(
        component: ImageAdjustmentDescription.ColorGrading.Component,
        tint: ImageAdjustmentDescription.ColorGrading.Tint,
        stops: Int = 25
    ) -> [SIMD3<Double>] {
        let gray = SIMD3<Double>(repeating: 0.5)
        var base = tint
        if component == .hue { base.saturation = 1 }

        return sweep(0 ... 1, stops: stops).map { value in
            var swept = base
            swept[component] = value

            let offset = ColorGradingTransform.tint(hue: swept.hue, saturation: swept.saturation)
            return ColorGradingTransform(tints: [offset, offset, offset], balance: 0)(gray)
        }
    }

    /// `stops` evenly spaced values from `range`'s lower bound to its upper, both included; at least two.
    private static func sweep(_ range: ClosedRange<Double>, stops: Int) -> [Double] {
        let count = max(2, stops)

        return (0 ..< count).map { stop in
            range.lowerBound + (range.upperBound - range.lowerBound) * Double(stop) / Double(count - 1)
        }
    }
}
