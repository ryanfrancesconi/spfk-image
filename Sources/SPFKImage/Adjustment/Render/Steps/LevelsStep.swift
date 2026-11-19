// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation

enum LevelsStep {
    static func apply(_ image: CIImage, _ levels: ImageAdjustmentDescription.Levels) -> CIImage {
        guard !levels.isNeutral else { return image }
        return ToneCurve.apply(image, curve(levels))
    }

    /// The levels points as `CIToneCurve` points: each ordered input position to its fixed output.
    static func curve(_ levels: ImageAdjustmentDescription.Levels) -> [CGPoint] {
        zip(levels.positions, ImageAdjustmentDescription.Levels.identity).map { CGPoint(x: $0, y: $1) }
    }
}
