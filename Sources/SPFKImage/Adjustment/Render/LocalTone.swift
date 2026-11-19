// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// The machinery ``BrillianceStep`` and ``DefinitionStep`` share: luminance split into an edge-aware
/// base and the detail above it.
///
/// Every step is relative to the extent, so a preview and the saved file match without `sourceScale`.
/// Core Image's blend modes clamp each channel to 0…1, so they only ever see luminance, offset to stay
/// inside it; the color image is changed through `CIMultiplyCompositing`, which does not clamp.
enum LocalTone {
    /// Multiplies every channel, in sRGB-encoded values, by `lp′ / lp`, where `lp` is the encoded
    /// luminance and `lp′ = curve(base) + detailGain × (lp − base)`. A ratio keeps hue, scales
    /// saturation with brightness, and cannot take a channel below 0.
    ///
    /// The ratio is taken on the image clamped to 0…1 and what lies outside is carried over, since
    /// `lp′` is clamped while `lp` is not and an HDR highlight would otherwise be pulled to white.
    static func apply(_ image: CIImage, curve: [CGPoint], detailGain: Double) -> CIImage {
        CIArithmetic.preservingRange(image) { image in
            inRange(image.applyingFilter("CIColorClamp"), curve: curve, detailGain: detailGain)
        }
    }

    private static func inRange(_ image: CIImage, curve: [CGPoint], detailGain: Double) -> CIImage {
        let extent = image.extent
        let luminance = CIArithmetic.encodedSRGB(CIArithmetic.rec709Luminance(image))
        let base = edgeAwareBase(luminance)
        let curved = CIArithmetic.encodedSRGB(ToneCurve.apply(CIArithmetic.decodedSRGB(base), curve))

        // 0.5 + (lp − base) / 2 stays inside 0…1; lp′ is clamped to it.
        let halfDetail = CIArithmetic.add(CIArithmetic.scale(luminance, 0.5), CIArithmetic.scale(base, -0.5, bias: 0.5))
        let adjusted = CIArithmetic.add(curved, CIArithmetic.scale(halfDetail, 2 * detailGain, bias: -detailGain))

        // CIDivideBlendMode returns min(1, background / input), so a quarter of the ratio is taken,
        // which keeps ratios up to 4.
        let quarterRatio = CIArithmetic.scale(luminance, 1, bias: ratioFloor).applyingFilter(
            "CIDivideBlendMode",
            parameters: [kCIInputBackgroundImageKey: CIArithmetic.scale(adjusted, 0.25, bias: ratioFloor / 4)]
        )
        let product = CIArithmetic.scale(quarterRatio, 4).applyingFilter(
            "CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: CIArithmetic.encodedSRGB(image)]
        )
        return CIArithmetic.decodedSRGB(product).cropped(to: extent)
    }

    /// `CIGuidedFilter` upsamples an input smaller than its guide along the guide's edges, and passes one
    /// the guide's size through unchanged; it writes red only, which is copied to green and blue.
    private static func edgeAwareBase(_ luminance: CIImage) -> CIImage {
        let extent = luminance.extent
        let factor = min(1, baseSize / Double(min(extent.width, extent.height)))
        // Whole-pixel dimensions: a fractional last column comes back from the filter as an edge artifact.
        let low = luminance.clampedToExtent()
            .applyingGaussianBlur(sigma: 0.5 / factor)
            .cropped(to: extent)
            .transformed(by: CGAffineTransform(
                scaleX: (extent.width * factor).rounded() / extent.width,
                y: (extent.height * factor).rounded() / extent.height
            ))

        let guided = CIFilter(name: "CIGuidedFilter", parameters: [
            kCIInputImageKey: low,
            "inputGuideImage": luminance,
            kCIInputRadiusKey: guideRadius,
            "inputEpsilon": epsilon,
        ])?.outputImage ?? luminance
        let red = CIVector(x: 1, y: 0, z: 0, w: 0)
        return CIArithmetic.matrix(guided.cropped(to: extent), r: red, g: red, b: red)
    }

    /// Added to both luminances before the ratio, so black does not divide by zero.
    static let ratioFloor: Double = 0.004
    /// The base's shorter side, in pixels, before it is upsampled along the image's edges.
    static let baseSize: Double = 128
    /// `CIGuidedFilter`'s radius and epsilon for the base; epsilon is in sRGB-encoded luminance squared.
    static let guideRadius: Double = 3
    static let epsilon: Double = 0.01
}
