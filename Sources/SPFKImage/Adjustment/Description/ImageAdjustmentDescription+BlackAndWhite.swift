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
