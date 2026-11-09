// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    /// Case order is display order; the renderer's order is fixed separately.
    public enum Parameter: String, CaseIterable, Codable, Sendable {
        case brilliance
        case exposure
        case highlights
        case shadows
        case brightness
        case contrast
        case blackPoint
        case whitePoint
        case saturation
        case vibrance
        case temperature
        case tint
        case sepia
        case blackAndWhite
        case blackAndWhiteRed
        case blackAndWhiteYellow
        case blackAndWhiteGreen
        case blackAndWhiteCyan
        case blackAndWhiteBlue
        case blackAndWhiteMagenta
        case levelsBlack
        case levelsShadow
        case levelsMid
        case levelsHighlight
        case levelsWhite
        case selectiveRedHue
        case selectiveRedSaturation
        case selectiveRedLuminance
        case selectiveYellowHue
        case selectiveYellowSaturation
        case selectiveYellowLuminance
        case selectiveGreenHue
        case selectiveGreenSaturation
        case selectiveGreenLuminance
        case selectiveCyanHue
        case selectiveCyanSaturation
        case selectiveCyanLuminance
        case selectiveBlueHue
        case selectiveBlueSaturation
        case selectiveBlueLuminance
        case selectiveMagentaHue
        case selectiveMagentaSaturation
        case selectiveMagentaLuminance
        case colorGradingShadowHue
        case colorGradingShadowSaturation
        case colorGradingMidtoneHue
        case colorGradingMidtoneSaturation
        case colorGradingHighlightHue
        case colorGradingHighlightSaturation
        case colorGradingBalance
        case sharpness
        case sharpnessRadius
        case definition
        case noiseReduction
        case vignette
        case vignetteRadius
        case vignetteSoftness
        case grain
        case grainSize

        /// Exposure is in stops; the rest are unitless positions. Highlights only go down: Core Image's
        /// highlight adjustment is at its maximum when neutral. Each levels offset keeps its point
        /// inside 0…1.
        public var range: ClosedRange<Double> {
            switch self {
            case .exposure: -3 ... 3
            case .highlights: -1 ... 0
            case .sepia, .blackAndWhite, .sharpness, .definition, .noiseReduction, .levelsBlack, .grain: 0 ... 1
            case .levelsShadow: -0.25 ... 0.75
            case .levelsMid: -0.5 ... 0.5
            case .levelsHighlight: -0.75 ... 0.25
            case .levelsWhite: -1 ... 0
            case .brilliance, .contrast, .shadows, .brightness, .blackPoint, .whitePoint, .saturation, .vibrance, .temperature, .tint,
                 .blackAndWhiteRed, .blackAndWhiteYellow, .blackAndWhiteGreen, .blackAndWhiteCyan, .blackAndWhiteBlue, .blackAndWhiteMagenta,
                 .sharpnessRadius, .vignette, .vignetteRadius, .vignetteSoftness, .grainSize: -1 ... 1
            case .selectiveRedHue, .selectiveRedSaturation, .selectiveRedLuminance,
                 .selectiveYellowHue, .selectiveYellowSaturation, .selectiveYellowLuminance,
                 .selectiveGreenHue, .selectiveGreenSaturation, .selectiveGreenLuminance,
                 .selectiveCyanHue, .selectiveCyanSaturation, .selectiveCyanLuminance,
                 .selectiveBlueHue, .selectiveBlueSaturation, .selectiveBlueLuminance,
                 .selectiveMagentaHue, .selectiveMagentaSaturation, .selectiveMagentaLuminance: -1 ... 1
            case .colorGradingShadowHue, .colorGradingShadowSaturation, .colorGradingMidtoneHue, .colorGradingMidtoneSaturation,
                 .colorGradingHighlightHue, .colorGradingHighlightSaturation: 0 ... 1
            case .colorGradingBalance: -1 ... 1
            }
        }

        public var keyPath: WritableKeyPath<ImageAdjustmentDescription, Double> {
            switch self {
            case .brilliance: \.light.brilliance
            case .exposure: \.light.exposure
            case .contrast: \.light.contrast
            case .highlights: \.light.highlights
            case .shadows: \.light.shadows
            case .brightness: \.light.brightness
            case .blackPoint: \.light.blackPoint
            case .whitePoint: \.light.whitePoint
            case .saturation: \.color.saturation
            case .vibrance: \.color.vibrance
            case .temperature: \.color.temperature
            case .tint: \.color.tint
            case .sepia: \.color.sepia
            case .blackAndWhite: \.blackAndWhite.amount
            case .blackAndWhiteRed: \.blackAndWhite.red
            case .blackAndWhiteYellow: \.blackAndWhite.yellow
            case .blackAndWhiteGreen: \.blackAndWhite.green
            case .blackAndWhiteCyan: \.blackAndWhite.cyan
            case .blackAndWhiteBlue: \.blackAndWhite.blue
            case .blackAndWhiteMagenta: \.blackAndWhite.magenta
            case .levelsBlack: \.levels.black
            case .levelsShadow: \.levels.shadow
            case .levelsMid: \.levels.mid
            case .levelsHighlight: \.levels.highlight
            case .levelsWhite: \.levels.white
            case .selectiveRedHue: \.selectiveColor.red.hue
            case .selectiveRedSaturation: \.selectiveColor.red.saturation
            case .selectiveRedLuminance: \.selectiveColor.red.luminance
            case .selectiveYellowHue: \.selectiveColor.yellow.hue
            case .selectiveYellowSaturation: \.selectiveColor.yellow.saturation
            case .selectiveYellowLuminance: \.selectiveColor.yellow.luminance
            case .selectiveGreenHue: \.selectiveColor.green.hue
            case .selectiveGreenSaturation: \.selectiveColor.green.saturation
            case .selectiveGreenLuminance: \.selectiveColor.green.luminance
            case .selectiveCyanHue: \.selectiveColor.cyan.hue
            case .selectiveCyanSaturation: \.selectiveColor.cyan.saturation
            case .selectiveCyanLuminance: \.selectiveColor.cyan.luminance
            case .selectiveBlueHue: \.selectiveColor.blue.hue
            case .selectiveBlueSaturation: \.selectiveColor.blue.saturation
            case .selectiveBlueLuminance: \.selectiveColor.blue.luminance
            case .selectiveMagentaHue: \.selectiveColor.magenta.hue
            case .selectiveMagentaSaturation: \.selectiveColor.magenta.saturation
            case .selectiveMagentaLuminance: \.selectiveColor.magenta.luminance
            case .colorGradingShadowHue: \.colorGrading.shadows.hue
            case .colorGradingShadowSaturation: \.colorGrading.shadows.saturation
            case .colorGradingMidtoneHue: \.colorGrading.midtones.hue
            case .colorGradingMidtoneSaturation: \.colorGrading.midtones.saturation
            case .colorGradingHighlightHue: \.colorGrading.highlights.hue
            case .colorGradingHighlightSaturation: \.colorGrading.highlights.saturation
            case .colorGradingBalance: \.colorGrading.balance
            case .sharpness: \.detail.sharpness
            case .sharpnessRadius: \.detail.sharpnessRadius
            case .definition: \.detail.definition
            case .noiseReduction: \.detail.noiseReduction
            case .vignette: \.vignette.amount
            case .vignetteRadius: \.vignette.radius
            case .vignetteSoftness: \.vignette.softness
            case .grain: \.grain.amount
            case .grainSize: \.grain.size
            }
        }

        /// `value` clamped to ``range``, or neutral when it is not finite.
        public func sanitize(_ value: Double) -> Double {
            guard value.isFinite else { return 0 }
            return min(max(value, range.lowerBound), range.upperBound)
        }
    }
}
