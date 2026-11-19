// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation

/// An adjustment computed from the image itself, setting only the fields it owns.
public enum ImageAutoAdjustment: Sendable, CaseIterable {
    /// Auto Adjust: white balance, then Core Image's automatic enhancement.
    case adjust
    /// Temperature and Tint neutralizing the image's near-gray pixels.
    case whiteBalance

    public var parameters: Set<ImageAdjustmentDescription.Parameter> {
        switch self {
        case .adjust: ImageAdjustmentDescription.Parameter.auto
        case .whiteBalance: ImageAdjustmentDescription.Parameter.autoWhiteBalance
        }
    }

    /// `image` is the unadjusted source, upright.
    public func analyze(_ image: CIImage) async -> ImageAdjustmentDescription {
        switch self {
        case .adjust: await AutoAnalysis.adjustments(for: image)
        case .whiteBalance: WhiteBalanceAnalysis.adjustments(for: image)
        }
    }
}

extension ImageAdjustmentDescription.Parameter {
    /// What Auto sets; it leaves the rest as they are.
    public static let auto: Set<Self> = Set([.temperature, .tint, .vibrance, .highlights, .shadows] + ImageAdjustmentDescription.Group.levels.parameters)

    /// What Auto White Balance sets.
    public static let autoWhiteBalance: Set<Self> = [.temperature, .tint]
}

extension ImageAdjustmentDescription {
    /// This adjustment with the fields `kind` owns taken from `auto`. What is bypassed is unchanged.
    public func applyingAuto(_ auto: ImageAdjustmentDescription, kind: ImageAutoAdjustment = .adjust) -> ImageAdjustmentDescription {
        var result = self
        for parameter in kind.parameters {
            result[parameter] = auto[parameter]
        }
        return result
    }
}
