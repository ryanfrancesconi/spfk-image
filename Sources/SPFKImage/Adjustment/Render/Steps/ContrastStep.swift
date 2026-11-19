// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation

enum ContrastStep {
    static func apply(_ image: CIImage, _ value: Double) -> CIImage {
        guard value != 0 else { return image }
        return ToneCurve.apply(image, curve(value))
    }

    /// Scales the inner points' distance from mid-gray by a gain, in sRGB-encoded values, so mid-gray,
    /// black and white stay fixed.
    static func curve(_ value: Double) -> [CGPoint] {
        let gain = value > 0
            ? 1 + value * (maximumGain - 1)
            : 1 + value * (1 - minimumGain)

        return ToneCurve.positions.map { x in
            x == 0 || x == 1 ? CGPoint(x: x, y: x) : CGPoint(x: x, y: 0.5 + (x - 0.5) * gain)
        }
    }

    // MARK: - Mapping from slider positions

    /// The curve's gain about mid-gray at full positive and full negative contrast. Above 2 the curve's
    /// quarter point would fall below black.
    static let maximumGain: Double = 1.7
    static let minimumGain: Double = 0.4
}
