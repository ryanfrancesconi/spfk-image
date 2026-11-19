// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SPFKBase

extension ImageAdjustmentRenderer {
    /// The part of `adjustments` that renders before the curves step: the levels input and levels.
    public static func curvesInput(of adjustments: ImageAdjustmentDescription) -> ImageAdjustmentDescription {
        histogramInput(to: .curves, of: adjustments)
    }

    /// The histogram of `source` as the curves step receives it, binned on sRGB-encoded values as the
    /// curves read them: the kept area of `cropEdit` only. Nil when Core Image produces no output.
    public func curvesHistogram(_ adjustments: ImageAdjustmentDescription, cropEdit: CropEdit = CropEdit(), source: CGImage) -> ImageHistogram? {
        histogram(of: source, cropEdit: cropEdit, rendering: Self.curvesInput(of: adjustments))
    }
}
