// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import simd

extension ImageAdjustmentRenderer {
    typealias ColorBand = ImageAdjustmentDescription.ColorBand

    static func selectiveColor(_ image: CIImage, _ selectiveColor: ImageAdjustmentDescription.SelectiveColor) -> CIImage {
        ColorCube.apply(SelectiveColorTransform(selectiveColor), to: image)
    }

    /// The colors `band`'s reference color takes as `component` moves across its range, from minimum to
    /// maximum, with `shift`'s other components applied. sRGB-encoded, as the renderer works. Range
    /// does not change the reference, which sits on the band's center, so its track is one color.
    public static func selectiveColorTrack(
        _ band: ImageAdjustmentDescription.ColorBand,
        component: ImageAdjustmentDescription.SelectiveColor.Component,
        shift: ImageAdjustmentDescription.SelectiveColor.Shift,
        stops: Int = 25
    ) -> [SIMD3<Double>] {
        let reference = HueBands.reference(band)
        let range = band.parameter(component).range
        let count = max(2, stops)

        return (0 ..< count).map { stop in
            var swept = shift
            swept[component] = range.lowerBound + (range.upperBound - range.lowerBound) * Double(stop) / Double(count - 1)

            let shifts = ColorBand.allCases.map { $0 == band ? SIMD3(swept.hue, swept.saturation, swept.luminance) : .zero }
            return SelectiveColorTransform(shifts: shifts)(reference)
        }
    }

    // MARK: - Mapping from slider positions

    /// Oklch degrees a full hue shift turns its band.
    static let maximumSelectiveHueShift: Double = 60
    /// How much of the lightness difference between its old and new hues' sRGB cusps a turned color
    /// takes on. Moving all of it keeps the most chroma; none keeps lightness and can leave none.
    static let selectiveHueLightnessShare: Double = 0.5
    /// Oklab lightness a full negative luminance shift takes from a fully colorful pixel.
    static let maximumSelectiveDarkening: Double = 0.35
    /// Oklab lightness a full positive luminance shift adds to a fully colorful pixel.
    static let maximumSelectiveLightening: Double = 0.12
    /// The chroma, max − min of sRGB-encoded channels, at which a pixel takes its band's whole shift.
    static let selectiveColorFullChroma: Double = 0.25
}
