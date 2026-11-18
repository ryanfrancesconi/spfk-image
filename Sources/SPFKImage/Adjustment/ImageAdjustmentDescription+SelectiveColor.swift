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
            SelectiveColor.Component.allCases.map(parameter)
        }

        public func parameter(_ component: SelectiveColor.Component) -> Parameter {
            switch component {
            case .hue: hue
            case .saturation: saturation
            case .luminance: luminance
            }
        }
    }

    /// Hue, saturation and luminance shifts for each ``ColorBand``.
    public struct SelectiveColor: Hashable, Sendable, Codable {
        /// One of a band's three shifts, in ``ColorBand/parameters`` order.
        public enum Component: CaseIterable, Sendable {
            case hue
            case saturation
            case luminance
        }

        public struct Shift: Hashable, Sendable, Codable {
            public var hue: Double
            public var saturation: Double
            public var luminance: Double

            public init(hue: Double = 0, saturation: Double = 0, luminance: Double = 0) {
                self.hue = hue
                self.saturation = saturation
                self.luminance = luminance
            }

            public subscript(component: Component) -> Double {
                get {
                    switch component {
                    case .hue: hue
                    case .saturation: saturation
                    case .luminance: luminance
                    }
                }
                set {
                    switch component {
                    case .hue: hue = newValue
                    case .saturation: saturation = newValue
                    case .luminance: luminance = newValue
                    }
                }
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

    /// Whether the image renders in monochrome, and how each ``ColorBand``'s gray is lightened or
    /// darkened in it.
    public struct BlackAndWhite: Hashable, Sendable, Codable {
        public var isOn: Bool
        /// No effect while ``isOn`` is false.
        public var red: Double
        public var yellow: Double
        public var green: Double
        public var cyan: Double
        public var blue: Double
        public var magenta: Double

        public init(
            isOn: Bool = false,
            red: Double = 0,
            yellow: Double = 0,
            green: Double = 0,
            cyan: Double = 0,
            blue: Double = 0,
            magenta: Double = 0
        ) {
            self.isOn = isOn
            self.red = red
            self.yellow = yellow
            self.green = green
            self.cyan = cyan
            self.blue = blue
            self.magenta = magenta
        }

        private enum CodingKeys: String, CodingKey {
            case isOn, red, yellow, green, cyan, blue, magenta
        }

        /// A missing key takes its default, so a description saved with other fields still loads.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                isOn: try c.decodeIfPresent(Bool.self, forKey: .isOn) ?? false,
                red: try c.decodeIfPresent(Double.self, forKey: .red) ?? 0,
                yellow: try c.decodeIfPresent(Double.self, forKey: .yellow) ?? 0,
                green: try c.decodeIfPresent(Double.self, forKey: .green) ?? 0,
                cyan: try c.decodeIfPresent(Double.self, forKey: .cyan) ?? 0,
                blue: try c.decodeIfPresent(Double.self, forKey: .blue) ?? 0,
                magenta: try c.decodeIfPresent(Double.self, forKey: .magenta) ?? 0
            )
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
