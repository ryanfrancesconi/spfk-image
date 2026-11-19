// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation

/// The renderer's steps. ``ImageAdjustmentRenderer/apply(_:to:sourceScale:grainSeed:)`` runs them in
/// case order. Each case has one `<Name>Step` type.
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

    /// `image` through this step, reading what ``reads`` names from `adjustments`.
    func apply(_ image: CIImage, _ adjustments: ImageAdjustmentDescription, _ frame: RenderFrame) -> CIImage {
        let light = adjustments.light
        let color = adjustments.color
        let detail = adjustments.detail

        return switch self {
        case .noiseReduction: NoiseReductionStep.apply(image, detail.noiseReduction, sourceScale: frame.sourceScale)
        case .exposure: ExposureStep.apply(image, light.exposure)
        case .whiteBalance: WhiteBalanceStep.apply(image, temperature: color.temperature, tint: color.tint)
        case .vibrance: VibranceStep.apply(image, color.vibrance)
        case .blackPoint: BlackPointStep.apply(image, light.blackPoint)
        case .whitePoint: WhitePointStep.apply(image, light.whitePoint)
        case .levels: LevelsStep.apply(image, adjustments.levels)
        case .curves: CurvesStep.apply(image, adjustments.curves)
        case .highlightsShadows: HighlightsShadowsStep.apply(image, highlights: light.highlights, shadows: light.shadows)
        case .brightness: BrightnessStep.apply(image, light.brightness)
        case .brilliance: BrillianceStep.apply(image, light.brilliance)
        case .contrast: ContrastStep.apply(image, light.contrast)
        case .saturation: SaturationStep.apply(image, color.saturation)
        case .definition: DefinitionStep.apply(image, detail.definition)
        case .selectiveColor: SelectiveColorStep.apply(image, adjustments.selectiveColor)
        case .blackAndWhite: BlackAndWhiteStep.apply(image, adjustments.blackAndWhite)
        case .colorGrading: ColorGradingStep.apply(image, adjustments.colorGrading)
        case .sepia: SepiaStep.apply(image, color.sepia)
        case .sharpness:
            SharpnessStep.apply(image, detail.sharpness, radius: detail.sharpnessRadius, sourceScale: frame.sourceScale)
        case .vignette: VignetteStep.apply(image, adjustments.vignette, extent: frame.extent)
        case .grain:
            GrainStep.apply(image, adjustments.grain, origin: frame.extent.origin, sourceScale: frame.sourceScale, seed: frame.grainSeed)
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
