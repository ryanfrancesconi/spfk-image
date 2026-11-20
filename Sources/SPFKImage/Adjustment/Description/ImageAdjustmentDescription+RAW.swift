// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    /// Controls only a RAW develop has. Each value is relative to the file's own default: 0 develops
    /// as shot, -1 turns the control off, and 1 takes it to its maximum.
    public struct RAW: Hashable, Sendable, Codable {
        public var colorNoiseReduction: Double
        public var moireReduction: Double

        public init(colorNoiseReduction: Double = 0, moireReduction: Double = 0) {
            self.colorNoiseReduction = colorNoiseReduction
            self.moireReduction = moireReduction
        }

        public var isNeutral: Bool { self == Self() }

        mutating func clamp() {
            clampField(&colorNoiseReduction, .colorNoiseReduction)
            clampField(&moireReduction, .moireReduction)
        }
    }
}
