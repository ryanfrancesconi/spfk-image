// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    /// One section of the description, in display order. The raw value is stable: it is stored.
    public enum Group: String, CaseIterable, Codable, Sendable {
        case light
        case color
        case blackAndWhite
        case curves
        case levels
        case selectiveColor
        case colorGrading
        case detail
        case raw
        case vignette
        case grain

        /// In `Parameter.allCases` order. Empty for Curves, whose points are not parameters.
        public var parameters: [Parameter] {
            Self.byGroup[self] ?? []
        }

        private static let byGroup = Dictionary(grouping: Parameter.allCases, by: \.group)
    }
}

extension ImageAdjustmentDescription.Parameter {
    public var group: ImageAdjustmentDescription.Group {
        switch self {
        case .brilliance, .exposure, .highlights, .shadows, .brightness, .contrast, .blackPoint, .whitePoint: .light
        case .saturation, .vibrance, .temperature, .tint, .sepia: .color
        case .blackAndWhiteRed, .blackAndWhiteYellow, .blackAndWhiteGreen, .blackAndWhiteCyan, .blackAndWhiteBlue,
             .blackAndWhiteMagenta: .blackAndWhite
        case .levelsBlack, .levelsShadow, .levelsMid, .levelsHighlight, .levelsWhite: .levels
        case .selectiveRedHue, .selectiveRedSaturation, .selectiveRedLuminance, .selectiveRedRange,
             .selectiveYellowHue, .selectiveYellowSaturation, .selectiveYellowLuminance, .selectiveYellowRange,
             .selectiveGreenHue, .selectiveGreenSaturation, .selectiveGreenLuminance, .selectiveGreenRange,
             .selectiveCyanHue, .selectiveCyanSaturation, .selectiveCyanLuminance, .selectiveCyanRange,
             .selectiveBlueHue, .selectiveBlueSaturation, .selectiveBlueLuminance, .selectiveBlueRange,
             .selectiveMagentaHue, .selectiveMagentaSaturation, .selectiveMagentaLuminance, .selectiveMagentaRange: .selectiveColor
        case .colorGradingShadowHue, .colorGradingShadowSaturation, .colorGradingMidtoneHue, .colorGradingMidtoneSaturation,
             .colorGradingHighlightHue, .colorGradingHighlightSaturation, .colorGradingBalance: .colorGrading
        case .sharpness, .sharpnessRadius, .definition, .noiseReduction: .detail
        case .colorNoiseReduction, .moireReduction, .lensCorrection: .raw
        case .vignette, .vignetteRadius, .vignetteSoftness: .vignette
        case .grain, .grainSize: .grain
        }
    }
}
