// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Brilliance and Definition: luminance split into an edge-aware base and the detail above it.
///
/// Every step is relative to the extent, so a preview and the saved file match without `sourceScale`.
/// Core Image's blend modes clamp each channel to 0…1, so they only ever see luminance, offset to stay
/// inside it; the color image is changed through `CIMultiplyCompositing`, which does not clamp.
extension ImageAdjustmentRenderer {
    /// Moves the base along ``brillianceCurve(_:)`` and strengthens the detail a little.
    static func brilliance(_ image: CIImage, _ value: Double) -> CIImage {
        let detail = value > 0 ? brillianceDetailGain : brillianceDarkDetailGain
        return localTone(image, curve: brillianceCurve(value), detailGain: 1 + abs(value) * detail)
    }

    /// Scales the detail above the base by `1 + value × maximumDefinitionGain`, darkening the base
    /// slightly.
    static func definition(_ image: CIImage, _ value: Double) -> CIImage {
        localTone(image, curve: lifted(by: definitionLift, value), detailGain: 1 + value * maximumDefinitionGain)
    }

    /// Mid-tone weighted: positive lifts the base along ``brillianceLift``, negative lowers it along
    /// ``brillianceDrop``. Black and white stay fixed.
    static func brillianceCurve(_ value: Double) -> [CGPoint] {
        lifted(by: value > 0 ? brillianceLift : brillianceDrop, value)
    }

    private static func lifted(by lift: [Double], _ value: Double) -> [CGPoint] {
        zip(curvePositions, lift).map { x, lift in CGPoint(x: x, y: x + value * lift) }
    }

    /// Multiplies every channel, in sRGB-encoded values, by `lp′ / lp`, where `lp` is the encoded
    /// luminance and `lp′ = curve(base) + detailGain × (lp − base)`. A ratio keeps hue, scales
    /// saturation with brightness, and cannot take a channel below 0.
    ///
    /// The ratio is taken on the image clamped to 0…1 and what lies outside is carried over, since
    /// `lp′` is clamped while `lp` is not and an HDR highlight would otherwise be pulled to white.
    private static func localTone(_ image: CIImage, curve: [CGPoint], detailGain: Double) -> CIImage {
        CIArithmetic.preservingRange(image) { image in
            localToneInRange(image.applyingFilter("CIColorClamp"), curve: curve, detailGain: detailGain)
        }
    }

    private static func localToneInRange(_ image: CIImage, curve: [CGPoint], detailGain: Double) -> CIImage {
        let extent = image.extent
        let luminance = CIArithmetic.encodedSRGB(CIArithmetic.rec709Luminance(image))
        let base = edgeAwareBase(luminance)
        let curved = CIArithmetic.encodedSRGB(toneCurve(CIArithmetic.decodedSRGB(base), curve))

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
        let factor = min(1, localToneBaseSize / Double(min(extent.width, extent.height)))
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
            kCIInputRadiusKey: localToneGuideRadius,
            "inputEpsilon": localToneEpsilon,
        ])?.outputImage ?? luminance
        let red = CIVector(x: 1, y: 0, z: 0, w: 0)
        return CIArithmetic.matrix(guided.cropped(to: extent), r: red, g: red, b: red)
    }
}
