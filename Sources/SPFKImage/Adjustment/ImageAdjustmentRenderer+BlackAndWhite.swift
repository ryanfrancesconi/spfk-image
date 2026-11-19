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
        let cube = ColorCube.apply(BlackAndWhiteTransform(blackAndWhite), to: image)
        return CIArithmetic.rec709Luminance(cube)
    }

    /// The grays `band`'s reference color becomes as its shift moves across its range, from minimum to
    /// maximum, with every other band at 0. sRGB-encoded.
    public static func blackAndWhiteTrack(_ band: ImageAdjustmentDescription.ColorBand, stops: Int = 25) -> [SIMD3<Double>] {
        let reference = HueBands.reference(band)
        let range = band.blackAndWhite.range
        let count = max(2, stops)

        return (0 ..< count).map { stop in
            let value = range.lowerBound + (range.upperBound - range.lowerBound) * Double(stop) / Double(count - 1)
            return BlackAndWhiteTransform(shifts: ColorBand.allCases.map { $0 == band ? value : 0 })(reference)
        }
    }

    // MARK: - Mapping from slider positions

    /// The share of the way to white or black a full band shift moves a fully colorful pixel's gray.
    static let maximumBlackAndWhiteShift: Double = 0.6
    /// The chroma, max − min of sRGB-encoded channels, at which a pixel takes its band's whole shift.
    static let blackAndWhiteFullChroma: Double = 0.4
}
