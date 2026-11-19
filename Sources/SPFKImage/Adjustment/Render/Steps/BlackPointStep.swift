// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation

enum BlackPointStep {
    static func apply(_ image: CIImage, _ value: Double) -> CIImage {
        guard value != 0 else { return image }
        return ToneCurve.apply(image, curve(value))
    }

    /// In sRGB-encoded values. Positive maps `value × maximum` and below to 0, then bends back toward
    /// identity, lowering the upper points by drop; negative is a straight line raising 0 to
    /// `−value × maximum`. White stays at 1.
    static func curve(_ value: Double) -> [CGPoint] {
        let shift = abs(value) * maximum

        guard value > 0 else {
            return ToneCurve.positions.map { x in CGPoint(x: x, y: shift + (1 - shift) * x) }
        }

        let upper = zip(ToneCurve.positions, drop).dropFirst(2).map { x, drop in CGPoint(x: x, y: x - value * drop) }
        let middle = CGPoint(x: (shift + upper[0].x) / 2, y: upper[0].y / 2)
        return [CGPoint(x: shift, y: 0), middle] + upper
    }

    // MARK: - Mapping from slider positions

    /// How far a full black point moves black, in sRGB-encoded values.
    static let maximum: Double = 0.25
    /// How far full positive black point lowers each of `ToneCurve.positions` from 0.5 up, in
    /// sRGB-encoded values.
    static let drop: [Double] = [0, 0, 0.05, 0.02, 0]
}
