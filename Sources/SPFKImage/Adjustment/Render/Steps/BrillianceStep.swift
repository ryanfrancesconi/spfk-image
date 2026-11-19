// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation

enum BrillianceStep {
    /// Moves the base along ``curve(_:)`` and strengthens the detail a little (see ``LocalTone``).
    static func apply(_ image: CIImage, _ value: Double) -> CIImage {
        guard value != 0 else { return image }

        let detail = value > 0 ? detailGain : darkDetailGain
        return LocalTone.apply(image, curve: curve(value), detailGain: 1 + abs(value) * detail)
    }

    /// Mid-tone weighted: positive lifts the base along ``lift``, negative lowers it along ``drop``.
    /// Black and white stay fixed.
    static func curve(_ value: Double) -> [CGPoint] {
        ToneCurve.lifted(by: value > 0 ? lift : drop, value)
    }

    // MARK: - Mapping from slider positions

    /// How far full positive and full negative brilliance move the base at each of
    /// `ToneCurve.positions`, in sRGB-encoded values.
    static let lift: [Double] = [0, 0.10, 0.14, 0.04, 0]
    static let drop: [Double] = [0, 0.10, 0.21, 0.04, 0]
    /// The detail gain added at full positive and full negative brilliance.
    static let detailGain: Double = 0.6
    static let darkDetailGain: Double = 0.2
}
