// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    public struct Light: Hashable, Sendable, Codable {
        /// Positive lifts shadows and holds highlights, region by region; negative deepens both.
        public var brilliance: Double
        /// Stops (EV).
        public var exposure: Double
        public var highlights: Double
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
    }

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
    }

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
    }

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
    }

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
    }
}
