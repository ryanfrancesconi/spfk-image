// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation

enum BrightnessStep {
    static func apply(_ image: CIImage, _ value: Double) -> CIImage {
        guard value != 0 else { return image }
        return ToneCurve.apply(image, curve(value))
    }

    /// Lifts or lowers the mid-tones along `4x(1 − x)`, so black and white stay fixed.
    static func curve(_ value: Double) -> [CGPoint] {
        ToneCurve.positions.map { x in
            CGPoint(x: x, y: x + value * maximumLift * 4 * x * (1 - x))
        }
    }

    // MARK: - Mapping from slider positions

    /// How far full brightness moves mid-gray, in sRGB-encoded values.
    static let maximumLift: Double = 0.2
}
