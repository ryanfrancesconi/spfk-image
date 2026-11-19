// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// `CIToneCurve`, shared by every step that moves tones along five points.
enum ToneCurve {
    /// The x positions of `CIToneCurve`'s five points at identity.
    static let positions: [Double] = [0, 0.25, 0.5, 0.75, 1]

    /// `CIToneCurve` works on sRGB-encoded values and clamps its output to 0…1, so a value outside
    /// 0…1 continues from the curve's end at 0 or 1 (see CIArithmetic/preservingRange(_:in:_:)).
    static func apply(_ image: CIImage, _ points: [CGPoint]) -> CIImage {
        CIArithmetic.preservingRange(image) { image in
            let filter = CIFilter.toneCurve()
            filter.inputImage = image
            filter.point0 = points[0]
            filter.point1 = points[1]
            filter.point2 = points[2]
            filter.point3 = points[3]
            filter.point4 = points[4]
            return filter.outputImage ?? image
        }
    }

    /// `positions`, each raised by `value × lift` at the same index.
    static func lifted(by lift: [Double], _ value: Double) -> [CGPoint] {
        zip(positions, lift).map { x, lift in CGPoint(x: x, y: x + value * lift) }
    }
}
