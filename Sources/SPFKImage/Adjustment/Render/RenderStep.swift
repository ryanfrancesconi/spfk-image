// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// The renderer's steps, in the order ``ImageAdjustmentRenderer/apply(_:to:sourceScale:grainSeed:)``
/// runs them. Each case has one `<Name>Step` type.
///
/// `apply` spells its calls out instead of iterating these, since it runs per video frame.
enum RenderStep: CaseIterable, Sendable {
    case noiseReduction
    case exposure
    case whiteBalance
    case vibrance
    case blackPoint
    case whitePoint
    case levels
    case curves
    case highlightsShadows
    case brightness
    case brilliance
    case contrast
    case saturation
    case definition
    case selectiveColor
    case blackAndWhite
    case colorGrading
    case sepia
    case sharpness
    case vignette
    case grain

    /// What a step reads from the description.
    enum Reads: Hashable, Sendable {
        case parameters([ImageAdjustmentDescription.Parameter])
        /// A whole section, including what is not a parameter: the curves' points, Black & White's switch.
        case group(ImageAdjustmentDescription.Group)
    }

    var reads: Reads {
        switch self {
        case .noiseReduction: .parameters([.noiseReduction])
        case .exposure: .parameters([.exposure])
        case .whiteBalance: .parameters([.temperature, .tint])
        case .vibrance: .parameters([.vibrance])
        case .blackPoint: .parameters([.blackPoint])
        case .whitePoint: .parameters([.whitePoint])
        case .levels: .group(.levels)
        case .curves: .group(.curves)
        case .highlightsShadows: .parameters([.highlights, .shadows])
        case .brightness: .parameters([.brightness])
        case .brilliance: .parameters([.brilliance])
        case .contrast: .parameters([.contrast])
        case .saturation: .parameters([.saturation])
        case .definition: .parameters([.definition])
        case .selectiveColor: .group(.selectiveColor)
        case .blackAndWhite: .group(.blackAndWhite)
        case .colorGrading: .group(.colorGrading)
        case .sepia: .parameters([.sepia])
        case .sharpness: .parameters([.sharpness, .sharpnessRadius])
        case .vignette: .group(.vignette)
        case .grain: .group(.grain)
        }
    }

    /// The steps that run before `step`.
    static func steps(before step: RenderStep) -> [RenderStep] {
        Array(allCases.prefix { $0 != step })
    }
}

extension ImageAdjustmentDescription {
    /// What renders (see ``effective``), holding only what `steps` read.
    func rendering(only steps: [RenderStep]) -> ImageAdjustmentDescription {
        let effective = effective
        var result = ImageAdjustmentDescription()

        for step in steps {
            switch step.reads {
            case let .parameters(parameters):
                for parameter in parameters {
                    result[parameter] = effective[parameter]
                }
            case let .group(group):
                result.take(group, from: effective)
            }
        }

        return result
    }
}
