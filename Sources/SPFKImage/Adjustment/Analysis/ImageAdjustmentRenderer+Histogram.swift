// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import SPFKBase

extension ImageAdjustmentRenderer {
    /// The part of `adjustments` that renders before the levels step, so its output is what the
    /// levels curve receives. Leaves out noise reduction, which smooths the image without moving its
    /// tones.
    public static func levelsInput(of adjustments: ImageAdjustmentDescription) -> ImageAdjustmentDescription {
        histogramInput(to: .levels, of: adjustments)
    }

    /// The part of `adjustments` that renders before the curves step: the levels input and levels.
    public static func curvesInput(of adjustments: ImageAdjustmentDescription) -> ImageAdjustmentDescription {
        histogramInput(to: .curves, of: adjustments)
    }

    /// What renders before `step`, without noise reduction.
    static func histogramInput(to step: RenderStep, of adjustments: ImageAdjustmentDescription) -> ImageAdjustmentDescription {
        adjustments.rendering(only: RenderStep.steps(before: step).filter { $0 != .noiseReduction })
    }

    /// The histogram of `source` as the levels step receives it, binned on sRGB-encoded values as the
    /// levels curve reads them: the kept area of `cropEdit` only. Nil when Core Image produces no output.
    public func levelsHistogram(_ adjustments: ImageAdjustmentDescription, cropEdit: CropEdit = CropEdit(), source: CGImage) -> ImageHistogram? {
        histogram(of: source, cropEdit: cropEdit, rendering: Self.levelsInput(of: adjustments))
    }

    /// The histogram of `source` as the curves step receives it, binned on sRGB-encoded values as the
    /// curves read them: the kept area of `cropEdit` only. Nil when Core Image produces no output.
    public func curvesHistogram(_ adjustments: ImageAdjustmentDescription, cropEdit: CropEdit = CropEdit(), source: CGImage) -> ImageHistogram? {
        histogram(of: source, cropEdit: cropEdit, rendering: Self.curvesInput(of: adjustments))
    }

    /// The histogram of `source`'s kept area with `partial` applied, binned on sRGB-encoded values.
    func histogram(of source: CGImage, cropEdit: CropEdit, rendering partial: ImageAdjustmentDescription) -> ImageHistogram? {
        autoreleasepool {
            let input = Self.apply(partial, to: cropEdit.apply(to: CIImage(cgImage: source)))

            let encoded = CIArithmetic.encodedSRGB(input)

            guard let rgb = ImageHistogram.bins(of: encoded, extent: input.extent, context: context),
                  let luminance = ImageHistogram.bins(of: CIArithmetic.rec709Luminance(encoded), extent: input.extent, context: context)
            else { return nil }

            return ImageHistogram(
                red: rgb.map(\.x),
                green: rgb.map(\.y),
                blue: rgb.map(\.z),
                luminance: luminance.map(\.x)
            )
        }
    }
}
