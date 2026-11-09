// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import SPFKBase

extension ImageAdjustmentRenderer {
    /// Core Image's automatic enhancement of `image`, as the fields Auto owns (see
    /// ``ImageAdjustmentDescription/Parameter/auto``); every other field is neutral.
    ///
    /// `image` is the unadjusted source, upright: the analysis detects faces, which is orientation
    /// sensitive. Face balance and red-eye have no field and are dropped.
    public static func autoAdjustments(for image: CIImage) -> ImageAdjustmentDescription {
        var result = ImageAdjustmentDescription()

        for filter in image.autoAdjustmentFilters(options: [.redEye: false]) {
            switch filter.name {
            case "CIVibrance":
                result.vibrance = number(filter, kCIInputAmountKey)

            case "CIToneCurve":
                let points = (0 ..< 5).compactMap { (filter.value(forKey: "inputPoint\($0)") as? CIVector)?.cgPointValue }
                guard points.count == 5 else { continue }
                result.levelsPositions = ImageAdjustmentDescription.levelsIdentity.map { inputPosition(of: $0, on: points) }

            case "CIHighlightShadowAdjust":
                result.shadows = number(filter, "inputShadowAmount")
                result.highlights = number(filter, "inputHighlightAmount") - 1

            default:
                Log.debug("Auto drops \(filter.name)")
            }
        }

        return result
    }

    /// `kind` for the file at `url`, analyzed at ``autoAnalysisSize`` with `orientation` applied.
    /// `nil` when it cannot be decoded. Security-scoped access is the caller's.
    public static func autoAdjustments(
        contentsOf url: URL,
        orientation: ImageOrientationEdit = .up,
        kind: ImageAutoAdjustment = .adjust
    ) -> ImageAdjustmentDescription? {
        autoreleasepool {
            guard let decoded = StillImageThumbnail.make(url: url, maxPixelSize: autoAnalysisSize, allowsEmbeddedThumbnail: false)
            else { return nil }

            return kind.analyze(orientation.apply(to: CIImage(cgImage: decoded)))
        }
    }

    /// The long edge Auto analyzes at, whatever the file's size, so a file gets the same result
    /// alone or in a batch.
    public static let autoAnalysisSize = 1024

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

/// An adjustment computed from the image itself, setting only the fields it owns.
public enum ImageAutoAdjustment: Sendable, CaseIterable {
    /// Core Image's automatic enhancement: Auto Adjust.
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
    public func analyze(_ image: CIImage) -> ImageAdjustmentDescription {
        switch self {
        case .adjust: ImageAdjustmentRenderer.autoAdjustments(for: image)
        case .whiteBalance: ImageAdjustmentRenderer.autoWhiteBalance(for: image)
        }
    }
}

extension ImageAdjustmentDescription.Parameter {
    /// What Auto sets; it leaves the rest as they are.
    public static let auto: Set<Self> = Set([.vibrance, .highlights, .shadows] + levels)

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
