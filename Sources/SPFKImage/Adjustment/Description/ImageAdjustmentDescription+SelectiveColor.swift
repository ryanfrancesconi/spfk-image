// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    /// Hue, saturation and luminance shifts for each ``ColorBand``, and how wide each band reaches.
    public struct SelectiveColor: Hashable, Sendable, Codable {
        /// One of a band's four values, in ``ColorBand/parameters`` order.
        public enum Component: CaseIterable, Sendable {
            case hue
            case saturation
            case luminance
            case range
        }

        public struct Shift: Hashable, Sendable, Codable {
            public var hue: Double
            public var saturation: Double
            public var luminance: Double
            /// The band's width as a power of two: −1 half as wide, 1 twice as wide. Moves nothing on
            /// its own.
            public var range: Double

            public init(hue: Double = 0, saturation: Double = 0, luminance: Double = 0, range: Double = 0) {
                self.hue = hue
                self.saturation = saturation
                self.luminance = luminance
                self.range = range
            }

            private enum CodingKeys: String, CodingKey {
                case hue, saturation, luminance, range
            }

            /// A missing key takes its default, so a description saved with other fields still loads.
            public init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.init(
                    hue: try c.decodeIfPresent(Double.self, forKey: .hue) ?? 0,
                    saturation: try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0,
                    luminance: try c.decodeIfPresent(Double.self, forKey: .luminance) ?? 0,
                    range: try c.decodeIfPresent(Double.self, forKey: .range) ?? 0
                )
            }

            public subscript(component: Component) -> Double {
                get {
                    switch component {
                    case .hue: hue
                    case .saturation: saturation
                    case .luminance: luminance
                    case .range: range
                    }
                }
                set {
                    switch component {
                    case .hue: hue = newValue
                    case .saturation: saturation = newValue
                    case .luminance: luminance = newValue
                    case .range: range = newValue
                    }
                }
            }

            mutating func clamp(_ band: ColorBand) {
                clampField(&hue, band.hue)
                clampField(&saturation, band.saturation)
                clampField(&luminance, band.luminance)
                clampField(&range, band.range)
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

        mutating func clamp() {
            red.clamp(.red)
            yellow.clamp(.yellow)
            green.clamp(.green)
            cyan.clamp(.cyan)
            blue.clamp(.blue)
            magenta.clamp(.magenta)
        }
    }
}
