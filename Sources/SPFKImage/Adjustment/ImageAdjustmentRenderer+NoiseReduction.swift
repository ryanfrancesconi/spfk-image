// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

extension ImageAdjustmentRenderer {
    /// A 3×3 median, which removes isolated speckles, then `CINoiseReduction` without its sharpening,
    /// mixed over `image` so the median's fixed strength fades in. Amount 0.5 and 1 match Photos'
    /// Noise Reduction at 1 and 2.
    ///
    /// Neither filter has a radius, so a downsampled preview passes `amount` scaled by its
    /// `sourceScale`: that is what the full-resolution result looks like once downsampled.
    static func noiseReduction(_ image: CIImage, _ amount: Double) -> CIImage {
        guard amount > 0 else { return image }

        let median = CIFilter.median()
        median.inputImage = image

        let reduce = CIFilter.noiseReduction()
        reduce.inputImage = median.outputImage
        reduce.noiseLevel = Float(amount * maximumNoiseLevel)
        reduce.sharpness = 0

        let mix = CIFilter.mix()
        mix.inputImage = reduce.outputImage
        mix.backgroundImage = image
        mix.amount = Float(maximumNoiseReductionMix * min(1, amount).squareRoot())

        return mix.outputImage?.cropped(to: image.extent) ?? image
    }

    /// `CINoiseReduction`'s noise level at full amount. Its effect stops growing near 0.05.
    static let maximumNoiseLevel: Double = 0.03
    /// How much of the denoised image is mixed in at full amount.
    static let maximumNoiseReductionMix: Double = 0.75
}
