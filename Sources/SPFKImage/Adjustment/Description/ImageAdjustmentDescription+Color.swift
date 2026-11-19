// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    public struct Color: Hashable, Sendable, Codable {
        public var saturation: Double
        public var vibrance: Double
        public var temperature: Double
        public var tint: Double
        public var sepia: Double

        public init(saturation: Double = 0, vibrance: Double = 0, temperature: Double = 0, tint: Double = 0, sepia: Double = 0) {
            self.saturation = saturation
            self.vibrance = vibrance
            self.temperature = temperature
            self.tint = tint
            self.sepia = sepia
        }

        public var isNeutral: Bool { self == Self() }

        mutating func clamp() {
            clampField(&saturation, .saturation)
            clampField(&vibrance, .vibrance)
            clampField(&temperature, .temperature)
            clampField(&tint, .tint)
            clampField(&sepia, .sepia)
        }
    }
}
