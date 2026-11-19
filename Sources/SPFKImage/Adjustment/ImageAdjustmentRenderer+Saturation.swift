// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

extension ImageAdjustmentRenderer {
    /// The Saturation step: ``SaturationTransform`` through a color cube for positive `amount`,
    /// `CIColorControls` for negative.
    static func saturation(_ image: CIImage, _ amount: Double) -> CIImage {
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

    // MARK: - Mapping from slider positions

    /// How much full positive Saturation adds to a color's Oklch chroma, as a multiple of it.
    static let maximumSaturationGain: Double = 1.6
}
