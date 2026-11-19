// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum SharpnessStep {
    /// `CISharpenLuminance` at `amount`, its radius scaled by `sourceScale` so a preview matches the
    /// saved file.
    static func apply(_ image: CIImage, _ amount: Double, radius: Double, sourceScale: Double) -> CIImage {
        guard amount != 0 else { return image }

        let filter = CIFilter.sharpenLuminance()
        filter.inputImage = image
        filter.sharpness = Float(amount * maximumSharpness)
        filter.radius = Float(neutralRadius * pow(2, radius) * sourceScale)
        return filter.outputImage ?? image
    }

    // MARK: - Mapping from slider positions

    /// Top of `CISharpenLuminance`'s slider range.
    static let maximumSharpness: Double = 2
    /// `CISharpenLuminance`'s default radius, in full-resolution pixels, used at a neutral sharpness
    /// radius. Each unit of radius doubles or halves it.
    static let neutralRadius: Double = 1.69
}
