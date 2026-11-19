// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

extension ImageAdjustmentRenderer {
    /// `image` in monochrome, in Core Image's linear working space.
    ///
    /// The cube passes values outside 0…1 through per channel, so its output is reduced to luminance
    /// once more: a gray is unchanged, and a wide-gamut or HDR remainder becomes gray too.
    static func blackAndWhite(_ image: CIImage, _ blackAndWhite: ImageAdjustmentDescription.BlackAndWhite) -> CIImage {
        let shifts = ColorBand.allCases.map { blackAndWhite[$0] }
        let cube = colorCube(image, step: "blackAndWhite", values: shifts, nodeTransform: { Self.blackAndWhite($0, shifts: shifts) })
        return CIArithmetic.rec709Luminance(cube)
    }

    static func blackAndWhite(_ rgb: SIMD3<Double>, shifts: [Double]) -> SIMD3<Double> {
        blackAndWhite(ColorCubeNode(rgb), shifts: shifts)
    }

    /// The gray for `node`: its Rec. 709 luminance, moved toward white or black by each band's shift
    /// in ``ColorBand`` order, weighed by ``HueBands/weight(hue:center:width:)`` and by
    /// how colorful the pixel is. Grays and near-grays take their luminance alone.
    static func blackAndWhite(_ node: ColorCubeNode, shifts: [Double]) -> SIMD3<Double> {
        let rgb = node.rgb
        let linear = SIMD3(ColorMath.sRGBDecoded(rgb.x), ColorMath.sRGBDecoded(rgb.y), ColorMath.sRGBDecoded(rgb.z))
        var gray = ColorMath.sRGBEncoded((linear * ColorMath.luminanceWeights).sum())

        if node.chroma > HueBands.minimumChroma {
            var shift = 0.0
            for (center, value) in zip(HueBands.centers, shifts) where value != 0 {
                shift += HueBands.weight(hue: node.hue, center: center) * value
            }
            shift *= HueBands.chromaGate(node.chroma, full: blackAndWhiteFullChroma) * maximumBlackAndWhiteShift
            gray += shift * (shift > 0 ? 1 - gray : gray)
        }

        return SIMD3(repeating: gray)
    }

    /// The grays `band`'s reference color becomes as its shift moves across its range, from minimum to
    /// maximum, with every other band at 0. sRGB-encoded.
    public static func blackAndWhiteTrack(_ band: ImageAdjustmentDescription.ColorBand, stops: Int = 25) -> [SIMD3<Double>] {
        let reference = HueBands.reference(band)
        let range = band.blackAndWhite.range
        let count = max(2, stops)

        return (0 ..< count).map { stop in
            let value = range.lowerBound + (range.upperBound - range.lowerBound) * Double(stop) / Double(count - 1)
            return blackAndWhite(reference, shifts: ColorBand.allCases.map { $0 == band ? value : 0 })
        }
    }

    // MARK: - Mapping from slider positions

    /// The share of the way to white or black a full band shift moves a fully colorful pixel's gray.
    static let maximumBlackAndWhiteShift: Double = 0.6
    /// The chroma, max − min of sRGB-encoded channels, at which a pixel takes its band's whole shift.
    static let blackAndWhiteFullChroma: Double = 0.4
}
