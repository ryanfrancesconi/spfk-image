// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

extension ImageAdjustmentRenderer {
    /// The Vibrance step: `CIVibrance` for positive `amount`, ``MutedVibranceTransform`` through a
    /// color cube for negative.
    static func vibrance(_ image: CIImage, _ amount: Double) -> CIImage {
        guard amount < 0 else {
            let filter = CIFilter.vibrance()
            filter.inputImage = image
            filter.amount = Float(amount)
            return filter.outputImage ?? image
        }

        return ColorCube.apply(MutedVibranceTransform(amount: amount), to: image)
    }

    // MARK: - Mapping from slider positions

    /// The share of its chroma a color away from skin keeps at full negative Vibrance.
    static let vibranceResidual: Double = 0.15
    /// The share of the mute a color at ``vibranceSkinHue`` is spared.
    static let vibranceSkinProtection: Double = 0.75
    /// Oklch hue, in degrees, of the skin tones negative Vibrance spares most.
    static let vibranceSkinHue: Double = 60
    /// Oklch degrees from ``vibranceSkinHue`` at which the protection reaches 0.
    static let vibranceSkinWidth: Double = 50
}
