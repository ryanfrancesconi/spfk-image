// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    public struct Detail: Hashable, Sendable, Codable {
        public var sharpness: Double
        /// How wide an edge sharpening reaches. Has no effect while ``sharpness`` is 0.
        public var sharpnessRadius: Double
        /// Local contrast: strengthens detail against its surroundings without halos at strong edges.
        public var definition: Double
        public var noiseReduction: Double

        public init(sharpness: Double = 0, sharpnessRadius: Double = 0, definition: Double = 0, noiseReduction: Double = 0) {
            self.sharpness = sharpness
            self.sharpnessRadius = sharpnessRadius
            self.definition = definition
            self.noiseReduction = noiseReduction
        }

        public var isNeutral: Bool { self == Self() }

        mutating func clamp() {
            clampField(&sharpness, .sharpness)
            clampField(&sharpnessRadius, .sharpnessRadius)
            clampField(&definition, .definition)
            clampField(&noiseReduction, .noiseReduction)
        }
    }
}
