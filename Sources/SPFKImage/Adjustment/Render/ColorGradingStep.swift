// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation

enum ColorGradingStep {
    /// ``ColorGradingTransform`` through a color cube.
    static func apply(_ image: CIImage, _ grading: ImageAdjustmentDescription.ColorGrading) -> CIImage {
        guard grading.hasTint else { return image }
        return ColorCube.apply(ColorGradingTransform(grading), to: image)
    }
}
