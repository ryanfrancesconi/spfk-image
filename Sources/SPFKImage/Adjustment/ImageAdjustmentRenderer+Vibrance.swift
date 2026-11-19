// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import simd

extension ImageAdjustmentRenderer {
    /// The Vibrance step: `CIVibrance` for positive `amount`, ``mutedVibrance(_:amount:)`` through a
    /// color cube for negative.
    static func vibrance(_ image: CIImage, _ amount: Double) -> CIImage {
        guard amount < 0 else {
            let filter = CIFilter.vibrance()
            filter.inputImage = image
            filter.amount = Float(amount)
            return filter.outputImage ?? image
        }

        return colorCube(image, step: "vibrance", values: [amount], nodeTransform: { mutedVibrance($0, amount: amount) })
    }

    /// `node`'s color with its Oklch chroma scaled toward ``vibranceResidual`` by `−amount`, holding
    /// lightness and hue. Skin hues keep ``vibranceSkinProtection`` of what they would lose.
    static func mutedVibrance(_ node: ColorCubeNode, amount: Double) -> SIMD3<Double> {
        let chroma = simd_length(SIMD2(node.oklab.y, node.oklab.z))
        guard chroma > 0 else { return node.rgb }

        let skin = HueBands.weight(hue: node.hue, center: vibranceSkinHue, width: vibranceSkinWidth)
        let scale = 1 + amount * (1 - vibranceResidual) * (1 - vibranceSkinProtection * skin)

        return ColorMath.sRGB(lightness: node.oklab.x, chroma: chroma * scale, hue: node.hue)
    }

    // MARK: - Mapping from slider positions

    /// The share of its chroma a color away from skin keeps at full negative Vibrance.
    static let vibranceResidual: Double = 0.15
    /// The share of the mute a color at ``vibranceSkinHue`` is spared.
    static let vibranceSkinProtection: Double = 0.75
    /// Oklch hue, in degrees, of the skin tones negative Vibrance spares most.
    static let vibranceSkinHue: Double = 60
    /// Oklch degrees from ``vibranceSkinHue`` at which the protection reaches 0.
    static let vibranceSkinWidth: Double = 50
}
