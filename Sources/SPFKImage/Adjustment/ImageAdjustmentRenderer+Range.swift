// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import simd

extension ImageAdjustmentRenderer {
    /// `step`'s output plus what clamping `image` to 0…1 removes, so values outside 0…1 (wide-gamut
    /// colors, HDR highlights) pass through a step that clamps them, taking the change their clamped
    /// value takes. An in-range pixel gets exactly `step`'s output.
    ///
    /// `step` must render a value outside 0…1 as it renders that value clamped, as Core Image's blend
    /// modes and color cubes do, and keep its input's alpha.
    ///
    /// `image` is read twice, so it renders once into an intermediate; otherwise every step upstream
    /// is evaluated once per read, doubling at each such step in a chain. With `.displayP3` the range
    /// is Display P3's, for a step working in that space; the working space is linear sRGB.
    static func preservingRange(_ image: CIImage, in space: ColorCubeSpace = .sRGB, _ step: (CIImage) -> CIImage) -> CIImage {
        let image = image.insertingIntermediate(cache: false)
        let negatedClamp: CIImage

        switch space {
        case .sRGB:
            negatedClamp = matrix(image.applyingFilter("CIColorClamp"), -matrix_identity_double3x3)
        case .displayP3:
            let clamped = matrix(image, linearSRGBToDisplayP3).applyingFilter("CIColorClamp")
            negatedClamp = matrix(clamped, -displayP3ToLinearSRGB)
        }

        let outOfRange = halvingAlpha(sum(image, negatedClamp))
        return halvingAlpha(sum(step(image), outOfRange)).cropped(to: image.extent)
    }

    /// `image` with its color channels multiplied by `transform`, alpha kept.
    static func matrix(_ image: CIImage, _ transform: simd_double3x3) -> CIImage {
        let row = { (index: Int) in
            CIVector(x: transform[0][index], y: transform[1][index], z: transform[2][index], w: 0)
        }
        return matrix(image, r: row(0), g: row(1), b: row(2))
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
