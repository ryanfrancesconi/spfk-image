// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import simd

/// Per-pixel arithmetic on images, in Core Image's linear working space unless a name says otherwise.
enum CIArithmetic {
    /// `image`'s color channels through the rows `r`, `g` and `b`, plus `bias`; alpha kept.
    static func matrix(_ image: CIImage, r: CIVector, g: CIVector, b: CIVector, bias: Double = 0) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = r
        filter.gVector = g
        filter.bVector = b
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        filter.biasVector = CIVector(x: bias, y: bias, z: bias, w: 0)
        return filter.outputImage ?? image
    }

    /// `image` with its color channels multiplied by `transform`, alpha kept.
    static func matrix(_ image: CIImage, _ transform: simd_double3x3) -> CIImage {
        let row = { (index: Int) in
            CIVector(x: transform[0][index], y: transform[1][index], z: transform[2][index], w: 0)
        }
        return matrix(image, r: row(0), g: row(1), b: row(2))
    }

    static func scale(_ image: CIImage, _ factor: Double, bias: Double = 0) -> CIImage {
        matrix(
            image,
            r: CIVector(x: factor, y: 0, z: 0, w: 0),
            g: CIVector(x: 0, y: factor, z: 0, w: 0),
            b: CIVector(x: 0, y: 0, z: factor, w: 0),
            bias: bias
        )
    }

    /// Clamps the sum to 0…1.
    static func add(_ image: CIImage, _ background: CIImage) -> CIImage {
        let filter = CIFilter.linearDodgeBlendMode()
        filter.inputImage = image
        filter.backgroundImage = background
        return filter.outputImage ?? image
    }

    /// `CIAdditionCompositing` does not clamp, but sums alpha as well as color.
    static func sum(_ image: CIImage, _ other: CIImage) -> CIImage {
        image.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: other])
    }

    /// The sum of two images of the same alpha, back at that alpha. Scaling by 2 is exact.
    static func halvingAlpha(_ image: CIImage) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: 2, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: 2, z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: 2, w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.5)
        return filter.outputImage ?? image
    }

    /// Linear values to sRGB-encoded ones.
    static func encodedSRGB(_ image: CIImage) -> CIImage {
        image.applyingFilter("CILinearToSRGBToneCurve")
    }

    /// sRGB-encoded values to linear ones.
    static func decodedSRGB(_ image: CIImage) -> CIImage {
        image.applyingFilter("CISRGBToneCurveToLinear")
    }

    /// Rec. 709 luminance in every color channel, of whatever encoding `image` holds.
    static func rec709Luminance(_ image: CIImage) -> CIImage {
        let weights = CIVector(x: ColorMath.luminanceWeights.x, y: ColorMath.luminanceWeights.y, z: ColorMath.luminanceWeights.z, w: 0)
        return matrix(image, r: weights, g: weights, b: weights)
    }

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
            let clamped = matrix(image, ColorMath.linearSRGBToDisplayP3).applyingFilter("CIColorClamp")
            negatedClamp = matrix(clamped, -ColorMath.displayP3ToLinearSRGB)
        }

        let outOfRange = halvingAlpha(sum(image, negatedClamp))
        return halvingAlpha(sum(step(image), outOfRange)).cropped(to: image.extent)
    }
}
