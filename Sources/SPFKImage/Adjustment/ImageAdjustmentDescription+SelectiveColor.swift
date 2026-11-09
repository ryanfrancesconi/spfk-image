// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    /// One of six color bands, each centered on a hue 60° from its neighbors. Selective Color shifts
    /// each band's color; Black & White lightens or darkens its gray.
    public enum SelectiveColor: String, CaseIterable, Sendable {
        case red
        case yellow
        case green
        case cyan
        case blue
        case magenta

        /// The band's center, in degrees around the HSL hue circle.
        public var centerHue: Double {
            switch self {
            case .red: 0
            case .yellow: 60
            case .green: 120
            case .cyan: 180
            case .blue: 240
            case .magenta: 300
            }
        }

        public var hue: Parameter {
            switch self {
            case .red: .selectiveRedHue
            case .yellow: .selectiveYellowHue
            case .green: .selectiveGreenHue
            case .cyan: .selectiveCyanHue
            case .blue: .selectiveBlueHue
            case .magenta: .selectiveMagentaHue
            }
        }

        public var saturation: Parameter {
            switch self {
            case .red: .selectiveRedSaturation
            case .yellow: .selectiveYellowSaturation
            case .green: .selectiveGreenSaturation
            case .cyan: .selectiveCyanSaturation
            case .blue: .selectiveBlueSaturation
            case .magenta: .selectiveMagentaSaturation
            }
        }

        public var luminance: Parameter {
            switch self {
            case .red: .selectiveRedLuminance
            case .yellow: .selectiveYellowLuminance
            case .green: .selectiveGreenLuminance
            case .cyan: .selectiveCyanLuminance
            case .blue: .selectiveBlueLuminance
            case .magenta: .selectiveMagentaLuminance
            }
        }

        /// How far Black & White lightens or darkens the band's gray.
        public var blackAndWhite: Parameter {
            switch self {
            case .red: .blackAndWhiteRed
            case .yellow: .blackAndWhiteYellow
            case .green: .blackAndWhiteGreen
            case .cyan: .blackAndWhiteCyan
            case .blue: .blackAndWhiteBlue
            case .magenta: .blackAndWhiteMagenta
            }
        }

        /// Hue, saturation and luminance, in that order.
        public var parameters: [Parameter] {
            [hue, saturation, luminance]
        }
    }

    /// Whether any Selective Color shift is away from neutral.
    public var hasSelectiveColor: Bool {
        Parameter.selectiveColor.contains { self[$0] != 0 }
    }
}

extension ImageAdjustmentDescription.Parameter {
    /// Every Selective Color parameter, band by band.
    public static let selectiveColor: [Self] = ImageAdjustmentDescription.SelectiveColor.allCases.flatMap(\.parameters)

    /// Black & White's band parameters, in band order.
    public static let blackAndWhiteBands: [Self] = ImageAdjustmentDescription.SelectiveColor.allCases.map(\.blackAndWhite)
}
