// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

extension ImageAdjustmentRenderer {
    /// Monochrome noise overlaid on `image`'s sRGB-encoded values, which leaves black and white
    /// untouched, keeps each tone's mean, and is strongest in the midtones.
    ///
    /// The noise is anchored at `origin` and sized in full-resolution pixels × `sourceScale`, so a
    /// preview shows the saved file's grain in the same place. Grain finer than one of `image`'s pixels
    /// cannot be drawn; it renders at one pixel with its strength scaled down by the same factor,
    /// which is what averaging the full-resolution grain into that pixel would do.
    static func grain(
        _ image: CIImage,
        amount: Double,
        size: Double,
        origin: CGPoint,
        sourceScale: Double
    ) -> CIImage {
        let cell = neutralGrainSize * pow(2, size) * sourceScale
        let strength = amount * maximumGrain * min(1, cell)
        let gain = CIVector(x: strength, y: 0, z: 0, w: 0)
        let offset = 0.5 - 0.5 * strength

        let centered = CIFilter.colorMatrix()
        centered.inputImage = grainNoise(cell: max(1, cell), origin: origin)
        centered.rVector = gain
        centered.gVector = gain
        centered.bVector = gain
        centered.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        centered.biasVector = CIVector(x: offset, y: offset, z: offset, w: 0)

        let encode = CIFilter.linearToSRGBToneCurve()
        encode.inputImage = image

        let overlay = CIFilter.overlayBlendMode()
        overlay.inputImage = centered.outputImage
        overlay.backgroundImage = encode.outputImage

        let decode = CIFilter.sRGBToneCurveToLinear()
        decode.inputImage = overlay.outputImage

        // The overlay of opaque noise is opaque; the source's own alpha is put back.
        let alpha = CIFilter.blendWithAlphaMask()
        alpha.inputImage = decode.outputImage
        alpha.backgroundImage = CIImage.empty()
        alpha.maskImage = image

        return alpha.outputImage ?? image
    }

    /// Uniform noise in 0…1, the same in every channel, with alpha 1. `CIRandomGenerator` repeats every
    /// 256 pixels, so two samples at different angles are averaged to hide the tile.
    private static func grainNoise(cell: Double, origin: CGPoint) -> CIImage? {
        guard let generator = CIFilter.randomGenerator().outputImage else { return nil }

        // A filter unpremultiplies its input, which would divide the noise by the generator's random alpha.
        let opaque = generator.settingAlphaOne(in: .infinite)

        func sample(angle: Double, channel: CIVector) -> CIImage? {
            let mono = CIFilter.colorMatrix()
            mono.inputImage = opaque
            mono.rVector = channel
            mono.gVector = channel
            mono.bVector = channel

            let transform = CGAffineTransform(translationX: origin.x, y: origin.y)
                .scaledBy(x: cell, y: cell)
                .rotated(by: angle)

            return mono.outputImage?.transformed(by: transform)
        }

        let mix = CIFilter.mix()
        mix.inputImage = sample(angle: 0.4, channel: CIVector(x: 1, y: 0, z: 0, w: 0))
        mix.backgroundImage = sample(angle: -1.1, channel: CIVector(x: 0, y: 1, z: 0, w: 0))
        mix.amount = 0.5
        return mix.outputImage
    }

    // MARK: - Mapping from slider positions

    /// The grain's size at neutral, in full-resolution pixels.
    static let neutralGrainSize: Double = 2
    /// The noise's gain at full grain. A midtone moves by up to half of it.
    static let maximumGrain: Double = 0.4
}
