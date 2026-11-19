// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    public struct Light: Hashable, Sendable, Codable {
        /// Positive lifts shadows and holds highlights, region by region; negative deepens both.
        public var brilliance: Double
        /// Stops (EV).
        public var exposure: Double
        /// Positive brightens the highlights; negative recovers them.
        public var highlights: Double
        /// Positive lifts the shadows and leaves the upper tones; negative deepens them.
        public var shadows: Double
        /// Moves the mid-tones and holds black and white.
        public var brightness: Double
        public var contrast: Double
        /// Positive crushes the darkest tones to black; negative lifts black to a gray floor.
        public var blackPoint: Double
        /// Positive clips the brightest tones to white; negative lowers white to a gray ceiling.
        public var whitePoint: Double

        public init(
            brilliance: Double = 0,
            exposure: Double = 0,
            highlights: Double = 0,
            shadows: Double = 0,
            brightness: Double = 0,
            contrast: Double = 0,
            blackPoint: Double = 0,
            whitePoint: Double = 0
        ) {
            self.brilliance = brilliance
            self.exposure = exposure
            self.highlights = highlights
            self.shadows = shadows
            self.brightness = brightness
            self.contrast = contrast
            self.blackPoint = blackPoint
            self.whitePoint = whitePoint
        }

        public var isNeutral: Bool { self == Self() }

        mutating func clamp() {
            clampField(&brilliance, .brilliance)
            clampField(&exposure, .exposure)
            clampField(&highlights, .highlights)
            clampField(&shadows, .shadows)
            clampField(&brightness, .brightness)
            clampField(&contrast, .contrast)
            clampField(&blackPoint, .blackPoint)
            clampField(&whitePoint, .whitePoint)
        }
    }
}
