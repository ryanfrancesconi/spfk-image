// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import simd

/// One encoded color with the coordinates the hue-based steps read.
struct ColorCubeNode: Sendable {
    let rgb: SIMD3<Double>
    let oklab: SIMD3<Double>
    /// Oklch hue in degrees, 0…360.
    let hue: Double
    /// Max − min of the encoded channels.
    let chroma: Double

    /// An sRGB-encoded color.
    init(_ rgb: SIMD3<Double>) {
        self.init(rgb, linearSRGB: Self.decoded(rgb))
    }

    /// A Display P3-encoded color.
    init(displayP3 rgb: SIMD3<Double>) {
        self.init(rgb, linearSRGB: ColorMath.displayP3ToLinearSRGB * Self.decoded(rgb))
    }

    private init(_ rgb: SIMD3<Double>, linearSRGB: SIMD3<Double>) {
        self.rgb = rgb
        oklab = ColorMath.oklab(linear: linearSRGB)
        hue = ColorMath.oklchHue(oklab)
        chroma = rgb.max() - rgb.min()
    }

    private static func decoded(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            ColorMath.sRGBDecoded(rgb.x),
            ColorMath.sRGBDecoded(rgb.y),
            ColorMath.sRGBDecoded(rgb.z)
        )
    }
}
