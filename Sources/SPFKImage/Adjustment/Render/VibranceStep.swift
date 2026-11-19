// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum VibranceStep {
    /// `CIVibrance` for positive `amount`, ``MutedVibranceTransform`` through a color cube for negative.
    static func apply(_ image: CIImage, _ amount: Double) -> CIImage {
        guard amount != 0 else { return image }

        guard amount < 0 else {
            let filter = CIFilter.vibrance()
            filter.inputImage = image
            filter.amount = Float(amount)
            return filter.outputImage ?? image
        }

        return ColorCube.apply(MutedVibranceTransform(amount: amount), to: image)
    }
}
