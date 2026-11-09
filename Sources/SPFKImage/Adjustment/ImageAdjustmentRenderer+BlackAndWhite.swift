// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

extension ImageAdjustmentRenderer {
    /// `image` mixed ``ImageAdjustmentDescription/blackAndWhite`` of the way to its channel mix, taken
    /// in Core Image's linear working space so neutral weights keep each pixel's luminance.
    static func blackAndWhite(_ image: CIImage, _ adjustments: ImageAdjustmentDescription) -> CIImage {
        let weights = blackAndWhiteWeights(
            red: adjustments.blackAndWhiteRed,
            green: adjustments.blackAndWhiteGreen,
            blue: adjustments.blackAndWhiteBlue
        )
        let row = CIVector(x: weights.x, y: weights.y, z: weights.z, w: 0)
        let mono = matrix(image, r: row, g: row, b: row)

        let mix = CIFilter.mix()
        mix.inputImage = mono
        mix.backgroundImage = image
        mix.amount = Float(adjustments.blackAndWhite)
        return mix.outputImage ?? image
    }

    /// The Rec. 709 luminance weights, each scaled by `2^value` and renormalized to sum to 1, so white
    /// stays white at any mix.
    static func blackAndWhiteWeights(red: Double, green: Double, blue: Double) -> SIMD3<Double> {
        let scaled = luminanceWeights * SIMD3(pow(2, red), pow(2, green), pow(2, blue))
        return scaled / scaled.sum()
    }

    // MARK: - Mapping from slider positions

    /// Rec. 709 luminance of linear red, green and blue.
    static let luminanceWeights = SIMD3<Double>(0.2126, 0.7152, 0.0722)
}
