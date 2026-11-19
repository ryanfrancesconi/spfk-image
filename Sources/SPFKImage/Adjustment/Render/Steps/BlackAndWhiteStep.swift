// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation

enum BlackAndWhiteStep {
    /// `image` in monochrome through ``BlackAndWhiteTransform``, in Core Image's linear working space.
    ///
    /// The cube passes values outside 0…1 through per channel, so its output is reduced to luminance
    /// once more: a gray is unchanged, and a wide-gamut or HDR remainder becomes gray too.
    static func apply(_ image: CIImage, _ blackAndWhite: ImageAdjustmentDescription.BlackAndWhite) -> CIImage {
        guard blackAndWhite.isOn else { return image }

        let cube = ColorCube.apply(BlackAndWhiteTransform(blackAndWhite), to: image)
        return CIArithmetic.rec709Luminance(cube)
    }
}
