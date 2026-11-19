// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum VignetteStep {
    /// Darkens or, when negative, lightens the edges of `extent`.
    static func apply(_ image: CIImage, _ vignette: ImageAdjustmentDescription.Vignette, extent: CGRect) -> CIImage {
        guard vignette.amount != 0 else { return image }

        let filter = CIFilter.vignetteEffect()
        filter.inputImage = image
        filter.center = CGPoint(x: extent.midX, y: extent.midY)
        filter.radius = Float(min(extent.width, extent.height) * neutralRadius * pow(2, vignette.radius))
        filter.falloff = Float(neutralFalloff * (1 + vignette.softness))
        filter.intensity = Float(vignette.amount)
        return filter.outputImage ?? image
    }

    // MARK: - Mapping from slider positions

    /// Where the vignette begins at a neutral radius, as a fraction of the shorter side. Each unit of
    /// radius doubles or halves it.
    static let neutralRadius: CGFloat = 0.75
    /// `CIVignetteEffect`'s falloff at neutral softness; the slider spans its 0…1.
    static let neutralFalloff: Double = 0.5
}
