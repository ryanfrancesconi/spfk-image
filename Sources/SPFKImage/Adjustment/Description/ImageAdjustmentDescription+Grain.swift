// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    /// Film grain over the finished image, strongest in the midtones.
    public struct Grain: Hashable, Sendable, Codable {
        public var amount: Double
        /// Each unit doubles or halves the grain. Has no effect while ``amount`` is 0.
        public var size: Double

        public init(amount: Double = 0, size: Double = 0) {
            self.amount = amount
            self.size = size
        }

        public var isNeutral: Bool { self == Self() }

        mutating func clamp() {
            clampField(&amount, .grain)
            clampField(&size, .grainSize)
        }
    }
}
