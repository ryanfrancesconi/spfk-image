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

        return colorCube(image, step: "saturation", values: [amount], nodeTransform: { saturated($0, amount: amount) })
    }

    /// `node`'s color with its Oklch chroma scaled by `1 + amount`, holding lightness and hue. A color
    /// the scale takes outside sRGB stops at its edge, so dull colors gain the most.
    static func saturated(_ node: ColorCubeNode, amount: Double) -> SIMD3<Double> {
        let chroma = simd_length(SIMD2(node.oklab.y, node.oklab.z))
        guard chroma > 0 else { return node.rgb }

        return sRGB(lightness: node.oklab.x, chroma: chroma * (1 + amount), hue: node.hue, insideChroma: chroma)
    }
}
