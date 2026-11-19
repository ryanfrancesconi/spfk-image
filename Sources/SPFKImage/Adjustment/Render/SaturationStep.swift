// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum SaturationStep {
    /// ``SaturationTransform`` through a color cube for positive `amount`, `CIColorControls` for
    /// negative.
    static func apply(_ image: CIImage, _ amount: Double) -> CIImage {
        guard amount != 0 else { return image }

        guard amount > 0 else {
            let filter = CIFilter.colorControls()
            filter.inputImage = image
            filter.contrast = 1
            filter.saturation = Float(1 + amount)
            filter.brightness = 0
            return filter.outputImage ?? image
        }

        return ColorCube.apply(SaturationTransform(amount: amount), to: image)
    }
}
