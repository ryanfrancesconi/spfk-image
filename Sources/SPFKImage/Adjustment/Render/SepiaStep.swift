// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum SepiaStep {
    /// `CISepiaTone` at `intensity`.
    static func apply(_ image: CIImage, _ intensity: Double) -> CIImage {
        guard intensity != 0 else { return image }

        let filter = CIFilter.sepiaTone()
        filter.inputImage = image
        filter.intensity = Float(intensity)
        return filter.outputImage ?? image
    }
}
