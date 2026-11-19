// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
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

        mutating func clamp() {
            clampField(&red, ColorBand.red.blackAndWhite)
            clampField(&yellow, ColorBand.yellow.blackAndWhite)
            clampField(&green, ColorBand.green.blackAndWhite)
            clampField(&cyan, ColorBand.cyan.blackAndWhite)
            clampField(&blue, ColorBand.blue.blackAndWhite)
            clampField(&magenta, ColorBand.magenta.blackAndWhite)
        }
    }
}
