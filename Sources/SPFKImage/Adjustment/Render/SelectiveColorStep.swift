// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation

enum SelectiveColorStep {
    /// ``SelectiveColorTransform`` through a color cube.
    static func apply(_ image: CIImage, _ selectiveColor: ImageAdjustmentDescription.SelectiveColor) -> CIImage {
        guard !selectiveColor.isNeutral else { return image }
        return ColorCube.apply(SelectiveColorTransform(selectiveColor), to: image)
    }
}
