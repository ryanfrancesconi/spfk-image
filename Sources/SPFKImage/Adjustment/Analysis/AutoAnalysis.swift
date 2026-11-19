// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import SPFKBase

/// Auto Adjust's analysis of an image.
enum AutoAnalysis {
    /// Auto Adjust for `image`: white balance, then Core Image's automatic enhancement of the balanced
    /// image, as the fields Auto owns (see ``ImageAdjustmentDescription/Parameter/auto``); every other
    /// field is neutral.
    ///
    /// The enhancement analyzes the balanced image because Temperature and Tint render before the
    /// levels it sets. `image` is the unadjusted source, upright: the analysis detects faces, which is
    /// orientation sensitive.
    static func adjustments(for image: CIImage) async -> ImageAdjustmentDescription {
        let balance = WhiteBalanceAnalysis.adjustments(for: image)
        let balanced = balance.color.temperature == 0 && balance.color.tint == 0
            ? image
            : WhiteBalanceStep.apply(image, temperature: balance.color.temperature, tint: balance.color.tint).cropped(to: image.extent)

        var result = await enhancement(for: balanced)
        result.color.temperature = balance.color.temperature
        result.color.tint = balance.color.tint
        return result
    }

    /// Core Image's automatic enhancement of `image` alone. Face balance and red-eye have no field and
    /// are dropped.
    static func enhancement(for image: CIImage) async -> ImageAdjustmentDescription {
        var result = ImageAdjustmentDescription()

        let filters = await BlockingCallLimiter.shared.run {
            image.autoAdjustmentFilters(options: [.redEye: false])
        }

        for filter in filters {
            switch filter.name {
            case "CIVibrance":
                result.color.vibrance = number(filter, kCIInputAmountKey)

            case "CIToneCurve":
                let points = (0 ..< 5).compactMap { (filter.value(forKey: "inputPoint\($0)") as? CIVector)?.cgPointValue }
                guard points.count == 5 else { continue }
                result.levels.positions = ImageAdjustmentDescription.Levels.identity.map { inputPosition(of: $0, on: points) }

            case "CIHighlightShadowAdjust":
                result.light.shadows = HighlightsShadowsStep.shadows(forShadowAmount: number(filter, "inputShadowAmount"))
                result.light.highlights = HighlightsShadowsStep.highlights(forHighlightAmount: number(filter, "inputHighlightAmount"))

            default:
                Log.debug("Auto drops \(filter.name)")
            }
        }

        return result
    }

    /// The input `points` map to `output`, read off the straight lines between them.
    static func inputPosition(of output: Double, on points: [CGPoint]) -> Double {
        guard let first = points.first, output > first.y else { return points.first.map { Double($0.x) } ?? output }

        for (a, b) in zip(points, points.dropFirst()) where Double(b.y) >= output {
            guard b.y > a.y else { return Double(b.x) }
            return Double(a.x) + (output - Double(a.y)) / Double(b.y - a.y) * Double(b.x - a.x)
        }

        return points.last.map { Double($0.x) } ?? output
    }

    private static func number(_ filter: CIFilter, _ key: String) -> Double {
        (filter.value(forKey: key) as? NSNumber)?.doubleValue ?? 0
    }
}
