// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    public struct Vignette: Hashable, Sendable, Codable {
        /// Negative lightens the edges.
        public var amount: Double
        /// How far from the center the vignette begins. Has no effect while ``amount`` is 0.
        public var radius: Double
        /// How gradual the vignette's edge is. Has no effect while ``amount`` is 0.
        public var softness: Double

        public init(amount: Double = 0, radius: Double = 0, softness: Double = 0) {
            self.amount = amount
            self.radius = radius
            self.softness = softness
        }

        public var isNeutral: Bool { self == Self() }

        mutating func clamp() {
            clampField(&amount, .vignette)
            clampField(&radius, .vignetteRadius)
            clampField(&softness, .vignetteSoftness)
        }
    }
}
