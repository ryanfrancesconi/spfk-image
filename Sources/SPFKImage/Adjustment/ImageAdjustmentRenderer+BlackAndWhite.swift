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
        let row = CIVector(x: luminanceWeights.x, y: luminanceWeights.y, z: luminanceWeights.z, w: 0)
        return matrix(cube, r: row, g: row, b: row)
    }

    static func blackAndWhite(_ rgb: SIMD3<Double>, shifts: [Double]) -> SIMD3<Double> {
        blackAndWhite(ColorCubeNode(rgb), shifts: shifts)
    }

    /// The gray for `node`: its Rec. 709 luminance, moved toward white or black by each band's shift
    /// in ``ColorBand`` order, weighed by Selective Color's ``bandWeight(hue:center:width:)`` and by
    /// how colorful the pixel is. Grays and near-grays take their luminance alone.
    static func blackAndWhite(_ node: ColorCubeNode, shifts: [Double]) -> SIMD3<Double> {
        let rgb = node.rgb
        let linear = SIMD3(sRGBDecoded(rgb.x), sRGBDecoded(rgb.y), sRGBDecoded(rgb.z))
        var gray = sRGBEncoded((linear * luminanceWeights).sum())

        if node.chroma > selectiveColorMinimumChroma {
            var shift = 0.0
            for (center, value) in zip(bandCenters, shifts) where value != 0 {
                shift += bandWeight(hue: node.hue, center: center) * value
            }
            shift *= chromaGate(node.chroma, full: blackAndWhiteFullChroma) * maximumBlackAndWhiteShift
            gray += shift * (shift > 0 ? 1 - gray : gray)
        }

        return SIMD3(repeating: gray)
    }

    /// The grays `band`'s reference color becomes as its shift moves across its range, from minimum to
    /// maximum, with every other band at 0. sRGB-encoded.
    public static func blackAndWhiteTrack(_ band: ImageAdjustmentDescription.ColorBand, stops: Int = 25) -> [SIMD3<Double>] {
        let reference = bandReference(band)
        let range = band.blackAndWhite.range
        let count = max(2, stops)

        return (0 ..< count).map { stop in
            let value = range.lowerBound + (range.upperBound - range.lowerBound) * Double(stop) / Double(count - 1)
            return blackAndWhite(reference, shifts: ColorBand.allCases.map { $0 == band ? value : 0 })
        }
    }

    static func sRGBDecoded(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    static func sRGBEncoded(_ value: Double) -> Double {
        value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    // MARK: - Mapping from slider positions

    /// Rec. 709 luminance of linear red, green and blue.
    static let luminanceWeights = SIMD3<Double>(0.2126, 0.7152, 0.0722)
    /// The share of the way to white or black a full band shift moves a fully colorful pixel's gray.
    static let maximumBlackAndWhiteShift: Double = 0.6
    /// The chroma, max − min of sRGB-encoded channels, at which a pixel takes its band's whole shift.
    static let blackAndWhiteFullChroma: Double = 0.4
}
