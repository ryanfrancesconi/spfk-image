// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    /// One of the three tonal ranges Color Grading tints separately.
    public enum ColorGradingRange: String, CaseIterable, Sendable {
        case shadows
        case midtones
        case highlights

        /// The tint's hue, 0…1 around the color circle from red.
        public var hue: Parameter {
            switch self {
            case .shadows: .colorGradingShadowHue
            case .midtones: .colorGradingMidtoneHue
            case .highlights: .colorGradingHighlightHue
            }
        }

        public var saturation: Parameter {
            switch self {
            case .shadows: .colorGradingShadowSaturation
            case .midtones: .colorGradingMidtoneSaturation
            case .highlights: .colorGradingHighlightSaturation
            }
        }
    }

    /// Whether any range carries a tint. Hue and balance alone render nothing.
    public var hasColorGrading: Bool {
        ColorGradingRange.allCases.contains { self[$0.saturation] != 0 }
    }
}

extension ImageAdjustmentDescription.Parameter {
    /// Every Color Grading parameter: each range's hue and saturation, then balance.
    public static let colorGrading: [Self] = ImageAdjustmentDescription.ColorGradingRange.allCases
        .flatMap { [$0.hue, $0.saturation] } + [.colorGradingBalance]
}
