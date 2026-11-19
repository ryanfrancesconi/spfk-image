// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// The gray for a color: its Rec. 709 luminance, moved toward white or black by each band's shift in
/// `ColorBand` order, weighed by HueBands/weight(hue:center:width:) and by how colorful the
/// pixel is. Grays and near-grays take their luminance alone.
struct BlackAndWhiteTransform: ColorCubeTransform {
    let shifts: [Double]

    init(shifts: [Double]) {
        self.shifts = shifts
    }

    init(_ blackAndWhite: ImageAdjustmentDescription.BlackAndWhite) {
        self.init(shifts: ImageAdjustmentDescription.ColorBand.allCases.map { blackAndWhite[$0] })
    }

    func callAsFunction(_ node: ColorCubeNode) -> SIMD3<Double> {
        let rgb = node.rgb
        let linear = SIMD3(ColorMath.sRGBDecoded(rgb.x), ColorMath.sRGBDecoded(rgb.y), ColorMath.sRGBDecoded(rgb.z))
        var gray = ColorMath.sRGBEncoded((linear * ColorMath.luminanceWeights).sum())

        if node.chroma > HueBands.minimumChroma {
            var shift = 0.0
            for (center, value) in zip(HueBands.centers, shifts) where value != 0 {
                shift += HueBands.weight(hue: node.hue, center: center) * value
            }
            shift *= HueBands.chromaGate(node.chroma, full: Self.fullChroma) * Self.maximumShift
            gray += shift * (shift > 0 ? 1 - gray : gray)
        }

        return SIMD3(repeating: gray)
    }

    // MARK: - Mapping from slider positions

    /// The share of the way to white or black a full band shift moves a fully colorful pixel's gray.
    static let maximumShift: Double = 0.6
    /// The chroma, max − min of sRGB-encoded channels, at which a pixel takes its band's whole shift.
    static let fullChroma: Double = 0.4
}
