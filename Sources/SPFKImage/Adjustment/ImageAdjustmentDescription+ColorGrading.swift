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

    /// A tint for each ``ColorGradingRange``, and where the ranges meet.
    public struct ColorGrading: Hashable, Sendable, Codable {
        /// A hue has no effect while its saturation is 0.
        public struct Tint: Hashable, Sendable, Codable {
            public var hue: Double
            public var saturation: Double

            public init(hue: Double = 0, saturation: Double = 0) {
                self.hue = hue
                self.saturation = saturation
            }
        }

        public var shadows: Tint
        public var midtones: Tint
        public var highlights: Tint
        /// Positive extends the highlights' tint into darker tones; negative extends the shadows'.
        public var balance: Double

        public init(shadows: Tint = Tint(), midtones: Tint = Tint(), highlights: Tint = Tint(), balance: Double = 0) {
            self.shadows = shadows
            self.midtones = midtones
            self.highlights = highlights
            self.balance = balance
        }

        public var isNeutral: Bool { self == Self() }

        /// Whether any range carries a tint. Hue and balance alone render nothing.
        public var hasTint: Bool {
            ColorGradingRange.allCases.contains { self[$0].saturation != 0 }
        }

        public subscript(range: ColorGradingRange) -> Tint {
            get {
                switch range {
                case .shadows: shadows
                case .midtones: midtones
                case .highlights: highlights
                }
            }
            set {
                switch range {
                case .shadows: shadows = newValue
                case .midtones: midtones = newValue
                case .highlights: highlights = newValue
                }
            }
        }
    }
}
