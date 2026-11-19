// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation

enum WhitePointStep {
    static func apply(_ image: CIImage, _ value: Double) -> CIImage {
        guard value != 0 else { return image }
        return ToneCurve.apply(image, curve(value))
    }

    /// A straight line in sRGB-encoded values. Positive maps `1 − value × maximum` to 1 and stretches
    /// the rest; negative lowers 1 to `1 + value × maximum`. Black stays at 0.
    static func curve(_ value: Double) -> [CGPoint] {
        let scale = 1 - abs(value) * maximum
        return ToneCurve.positions.map { x in
            value > 0
                ? CGPoint(x: scale * x, y: x)
                : CGPoint(x: x, y: scale * x)
        }
    }

    // MARK: - Mapping from slider positions

    /// How far a full white point moves white, in sRGB-encoded values.
    static let maximum: Double = 0.25
}
