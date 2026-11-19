// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum ExposureStep {
    /// `CIExposureAdjust` at `exposure` stops.
    static func apply(_ image: CIImage, _ exposure: Double) -> CIImage {
        guard exposure != 0 else { return image }

        let filter = CIFilter.exposureAdjust()
        filter.inputImage = image
        filter.ev = Float(exposure)
        return filter.outputImage ?? image
    }
}
