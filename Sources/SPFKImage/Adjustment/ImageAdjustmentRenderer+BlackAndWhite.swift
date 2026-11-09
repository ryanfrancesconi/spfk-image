// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

extension ImageAdjustmentRenderer {
    /// `image` mixed ``ImageAdjustmentDescription/blackAndWhite`` of the way to its monochrome version,
    /// in Core Image's linear working space.
    ///
    /// The cube passes values outside 0…1 through per channel, so its output is reduced to luminance
    /// once more: a gray is unchanged, and a wide-gamut or HDR remainder becomes gray too.
    static func blackAndWhite(_ image: CIImage, _ adjustments: ImageAdjustmentDescription) -> CIImage {
        let shifts = ImageAdjustmentDescription.Parameter.blackAndWhiteBands.map { adjustments[$0] }
        let cube = colorCube(image, step: "blackAndWhite", values: shifts) { blackAndWhite($0, shifts: shifts) }
        let row = CIVector(x: luminanceWeights.x, y: luminanceWeights.y, z: luminanceWeights.z, w: 0)
        let mono = matrix(cube, r: row, g: row, b: row)

        let mix = CIFilter.mix()
        mix.inputImage = mono
        mix.backgroundImage = image
        mix.amount = Float(adjustments.blackAndWhite)
        return mix.outputImage ?? image
    }

    /// The gray for sRGB-encoded `rgb`: its Rec. 709 luminance, moved toward white or black by each
    /// band's shift in ``SelectiveColor`` order, weighed by how close the pixel's hue is to the band and
    /// by how colorful it is. Grays and near-grays take their luminance alone.
    static func blackAndWhite(_ rgb: SIMD3<Double>, shifts: [Double]) -> SIMD3<Double> {
        let linear = SIMD3(sRGBDecoded(rgb.x), sRGBDecoded(rgb.y), sRGBDecoded(rgb.z))
        var gray = sRGBEncoded((linear * luminanceWeights).sum())

        let chroma = rgb.max() - rgb.min()
        if chroma > selectiveColorMinimumChroma {
            let hue = hsl(rgb).hue
            var shift = 0.0
            for (band, value) in zip(SelectiveColor.allCases, shifts) {
                shift += bandWeight(hue: hue, band) * value
            }
            shift *= chromaGate(chroma, full: blackAndWhiteFullChroma) * maximumBlackAndWhiteShift
            gray += shift * (shift > 0 ? 1 - gray : gray)
        }

        return SIMD3(repeating: gray)
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
