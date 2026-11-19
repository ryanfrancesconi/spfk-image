// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

extension ImageAdjustmentRenderer {
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
}
