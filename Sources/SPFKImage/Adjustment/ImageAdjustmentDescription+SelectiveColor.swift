// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    /// One of six color bands, each centered on a hue 60° from its neighbors. Selective Color shifts
    /// each band's color; Black & White lightens or darkens its gray.
    public enum ColorBand: String, CaseIterable, Sendable {
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

        /// Selective Color's hue, saturation and luminance, in that order.
        public var parameters: [Parameter] {
            [hue, saturation, luminance]
        }
    }

    /// Hue, saturation and luminance shifts for each ``ColorBand``.
    public struct SelectiveColor: Hashable, Sendable, Codable {
        public struct Shift: Hashable, Sendable, Codable {
            public var hue: Double
            public var saturation: Double
            public var luminance: Double

            public init(hue: Double = 0, saturation: Double = 0, luminance: Double = 0) {
                self.hue = hue
                self.saturation = saturation
                self.luminance = luminance
            }
        }

        public var red: Shift
        public var yellow: Shift
        public var green: Shift
        public var cyan: Shift
        public var blue: Shift
        public var magenta: Shift

        public init(
            red: Shift = Shift(),
            yellow: Shift = Shift(),
            green: Shift = Shift(),
            cyan: Shift = Shift(),
            blue: Shift = Shift(),
            magenta: Shift = Shift()
        ) {
            self.red = red
            self.yellow = yellow
            self.green = green
            self.cyan = cyan
            self.blue = blue
            self.magenta = magenta
        }

        public var isNeutral: Bool { self == Self() }

        public subscript(band: ColorBand) -> Shift {
            get {
                switch band {
                case .red: red
                case .yellow: yellow
                case .green: green
                case .cyan: cyan
                case .blue: blue
                case .magenta: magenta
                }
            }
            set {
                switch band {
                case .red: red = newValue
                case .yellow: yellow = newValue
                case .green: green = newValue
                case .cyan: cyan = newValue
                case .blue: blue = newValue
                case .magenta: magenta = newValue
                }
            }
        }
    }

    /// How far the image moves to its monochrome version, and how each ``ColorBand``'s gray is
    /// lightened or darkened in it.
    public struct BlackAndWhite: Hashable, Sendable, Codable {
        public var amount: Double
        /// No effect while ``amount`` is 0.
        public var red: Double
        public var yellow: Double
        public var green: Double
        public var cyan: Double
        public var blue: Double
        public var magenta: Double

        public init(
            amount: Double = 0,
            red: Double = 0,
            yellow: Double = 0,
            green: Double = 0,
            cyan: Double = 0,
            blue: Double = 0,
            magenta: Double = 0
        ) {
            self.amount = amount
            self.red = red
            self.yellow = yellow
            self.green = green
            self.cyan = cyan
            self.blue = blue
            self.magenta = magenta
        }

        public var isNeutral: Bool { self == Self() }

        public subscript(band: ColorBand) -> Double {
            switch band {
            case .red: red
            case .yellow: yellow
            case .green: green
            case .cyan: cyan
            case .blue: blue
            case .magenta: magenta
            }
        }
    }
}
