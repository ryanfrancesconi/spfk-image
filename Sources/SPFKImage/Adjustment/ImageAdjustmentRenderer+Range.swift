// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

extension ImageAdjustmentRenderer {
    /// `step`'s output plus what clamping `image` to 0…1 removes, so values outside 0…1 (wide-gamut
    /// colors, HDR highlights) pass through a step that clamps them, taking the change their clamped
    /// value takes. An in-range pixel gets exactly `step`'s output.
    ///
    /// `step` must render a value outside 0…1 as it renders that value clamped, as Core Image's blend
    /// modes and color cubes do, and keep its input's alpha.
    ///
    /// `image` is read twice, so it renders once into an intermediate; otherwise every step upstream
    /// is evaluated once per read, doubling at each such step in a chain.
    static func preservingRange(_ image: CIImage, _ step: (CIImage) -> CIImage) -> CIImage {
        let image = image.insertingIntermediate(cache: false)
        let negatedClamp = matrix(
            image.applyingFilter("CIColorClamp"),
            r: CIVector(x: -1, y: 0, z: 0, w: 0),
            g: CIVector(x: 0, y: -1, z: 0, w: 0),
            b: CIVector(x: 0, y: 0, z: -1, w: 0)
        )

        let outOfRange = halvingAlpha(sum(image, negatedClamp))
        return halvingAlpha(sum(step(image), outOfRange)).cropped(to: image.extent)
    }

    /// `CIAdditionCompositing` does not clamp, but sums alpha as well as color.
    private static func sum(_ image: CIImage, _ other: CIImage) -> CIImage {
        image.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: other])
    }

    /// The sum of two images of the same alpha, back at that alpha. Scaling by 2 is exact.
    private static func halvingAlpha(_ image: CIImage) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: 2, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: 2, z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: 2, w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.5)
        return filter.outputImage ?? image
    }
}
