// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import simd

extension ImageAdjustmentRenderer {
    /// The Saturation step: ``saturated(_:amount:)`` through a color cube for positive `amount`,
    /// `CIColorControls` for negative.
    static func saturation(_ image: CIImage, _ amount: Double) -> CIImage {
        guard amount > 0 else {
            let filter = CIFilter.colorControls()
            filter.inputImage = image
            filter.contrast = 1
            filter.saturation = Float(1 + amount)
            filter.brightness = 0
            return filter.outputImage ?? image
        }

        return colorCube(image, step: "saturation", values: [amount], space: .displayP3, nodeTransform: { saturated($0, amount: amount) })
    }

    /// Display P3-encoded `node`'s color with its Oklch chroma scaled by
    /// `1 + amount × maximumSaturationGain`, holding lightness and hue. A color the scale takes outside
    /// Display P3 stops at its edge, so dull colors gain the most.
    static func saturated(_ node: ColorCubeNode, amount: Double) -> SIMD3<Double> {
        let chroma = simd_length(SIMD2(node.oklab.y, node.oklab.z))
        guard chroma > 0 else { return node.rgb }

        let target = chroma * (1 + amount * maximumSaturationGain)
        return displayP3(lightness: node.oklab.x, chroma: target, hue: node.hue, insideChroma: chroma)
    }

    // MARK: - Mapping from slider positions

    /// How much full positive Saturation adds to a color's Oklch chroma, as a multiple of it.
    static let maximumSaturationGain: Double = 1.6
}
