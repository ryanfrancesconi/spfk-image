// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    /// Case order is display order; the renderer's order is fixed separately.
    public enum Parameter: String, CaseIterable, Codable, Sendable {
        case zoom
        case zoomCenterX
        case zoomCenterY
        case brilliance
        case exposure
        case highlights
        case shadows
        case brightness
        case contrast
        case blackPoint
        case whitePoint
        case saturation
        case vibrance
        case temperature
        case tint
        case sepia
        case blackAndWhite
        case blackAndWhiteRed
        case blackAndWhiteGreen
        case blackAndWhiteBlue
        case levelsBlack
        case levelsShadow
        case levelsMid
        case levelsHighlight
        case levelsWhite
        case selectiveRedHue
        case selectiveRedSaturation
        case selectiveRedLuminance
        case selectiveYellowHue
        case selectiveYellowSaturation
        case selectiveYellowLuminance
        case selectiveGreenHue
        case selectiveGreenSaturation
        case selectiveGreenLuminance
        case selectiveCyanHue
        case selectiveCyanSaturation
        case selectiveCyanLuminance
        case selectiveBlueHue
        case selectiveBlueSaturation
        case selectiveBlueLuminance
        case selectiveMagentaHue
        case selectiveMagentaSaturation
        case selectiveMagentaLuminance
        case colorGradingShadowHue
        case colorGradingShadowSaturation
        case colorGradingMidtoneHue
        case colorGradingMidtoneSaturation
        case colorGradingHighlightHue
        case colorGradingHighlightSaturation
        case colorGradingBalance
        case sharpness
        case sharpnessRadius
        case definition
        case noiseReduction
        case vignette
        case vignetteRadius
        case vignetteSoftness
        case grain
        case grainSize

        /// The parameters that describe the preview rather than the image.
        public static let viewState: [Parameter] = [.zoom, .zoomCenterX, .zoomCenterY]

        /// Whether this describes how the preview shows the image: it never renders and never makes a
        /// file dirty.
        public var isViewState: Bool {
            Self.viewState.contains(self)
        }

        /// Exposure is in stops; the rest are unitless positions. Highlights only go down: Core Image's
        /// highlight adjustment is at its maximum when neutral. Each levels offset keeps its point
        /// inside 0…1.
        public var range: ClosedRange<Double> {
            switch self {
            case .exposure: -3 ... 3
            case .highlights: -1 ... 0
            case .sepia, .blackAndWhite, .sharpness, .definition, .noiseReduction, .levelsBlack, .grain, .zoom: 0 ... 1
            case .zoomCenterX, .zoomCenterY: -0.5 ... 0.5
            case .levelsShadow: -0.25 ... 0.75
            case .levelsMid: -0.5 ... 0.5
            case .levelsHighlight: -0.75 ... 0.25
            case .levelsWhite: -1 ... 0
            case .brilliance, .contrast, .shadows, .brightness, .blackPoint, .whitePoint, .saturation, .vibrance, .temperature, .tint,
                 .blackAndWhiteRed, .blackAndWhiteGreen, .blackAndWhiteBlue,
                 .sharpnessRadius, .vignette, .vignetteRadius, .vignetteSoftness, .grainSize: -1 ... 1
            case .selectiveRedHue, .selectiveRedSaturation, .selectiveRedLuminance,
                 .selectiveYellowHue, .selectiveYellowSaturation, .selectiveYellowLuminance,
                 .selectiveGreenHue, .selectiveGreenSaturation, .selectiveGreenLuminance,
                 .selectiveCyanHue, .selectiveCyanSaturation, .selectiveCyanLuminance,
                 .selectiveBlueHue, .selectiveBlueSaturation, .selectiveBlueLuminance,
                 .selectiveMagentaHue, .selectiveMagentaSaturation, .selectiveMagentaLuminance: -1 ... 1
            case .colorGradingShadowHue, .colorGradingShadowSaturation, .colorGradingMidtoneHue, .colorGradingMidtoneSaturation,
                 .colorGradingHighlightHue, .colorGradingHighlightSaturation: 0 ... 1
            case .colorGradingBalance: -1 ... 1
            }
        }

        public var keyPath: WritableKeyPath<ImageAdjustmentDescription, Double> {
            switch self {
            case .brilliance: \.brilliance
            case .exposure: \.exposure
            case .contrast: \.contrast
            case .highlights: \.highlights
            case .shadows: \.shadows
            case .brightness: \.brightness
            case .blackPoint: \.blackPoint
            case .whitePoint: \.whitePoint
            case .saturation: \.saturation
            case .vibrance: \.vibrance
            case .temperature: \.temperature
            case .tint: \.tint
            case .sepia: \.sepia
            case .blackAndWhite: \.blackAndWhite
            case .blackAndWhiteRed: \.blackAndWhiteRed
            case .blackAndWhiteGreen: \.blackAndWhiteGreen
            case .blackAndWhiteBlue: \.blackAndWhiteBlue
            case .levelsBlack: \.levelsBlack
            case .levelsShadow: \.levelsShadow
            case .levelsMid: \.levelsMid
            case .levelsHighlight: \.levelsHighlight
            case .levelsWhite: \.levelsWhite
            case .selectiveRedHue: \.selectiveRedHue
            case .selectiveRedSaturation: \.selectiveRedSaturation
            case .selectiveRedLuminance: \.selectiveRedLuminance
            case .selectiveYellowHue: \.selectiveYellowHue
            case .selectiveYellowSaturation: \.selectiveYellowSaturation
            case .selectiveYellowLuminance: \.selectiveYellowLuminance
            case .selectiveGreenHue: \.selectiveGreenHue
            case .selectiveGreenSaturation: \.selectiveGreenSaturation
            case .selectiveGreenLuminance: \.selectiveGreenLuminance
            case .selectiveCyanHue: \.selectiveCyanHue
            case .selectiveCyanSaturation: \.selectiveCyanSaturation
            case .selectiveCyanLuminance: \.selectiveCyanLuminance
            case .selectiveBlueHue: \.selectiveBlueHue
            case .selectiveBlueSaturation: \.selectiveBlueSaturation
            case .selectiveBlueLuminance: \.selectiveBlueLuminance
            case .selectiveMagentaHue: \.selectiveMagentaHue
            case .selectiveMagentaSaturation: \.selectiveMagentaSaturation
            case .selectiveMagentaLuminance: \.selectiveMagentaLuminance
            case .colorGradingShadowHue: \.colorGradingShadowHue
            case .colorGradingShadowSaturation: \.colorGradingShadowSaturation
            case .colorGradingMidtoneHue: \.colorGradingMidtoneHue
            case .colorGradingMidtoneSaturation: \.colorGradingMidtoneSaturation
            case .colorGradingHighlightHue: \.colorGradingHighlightHue
            case .colorGradingHighlightSaturation: \.colorGradingHighlightSaturation
            case .colorGradingBalance: \.colorGradingBalance
            case .sharpness: \.sharpness
            case .sharpnessRadius: \.sharpnessRadius
            case .definition: \.definition
            case .noiseReduction: \.noiseReduction
            case .vignette: \.vignette
            case .vignetteRadius: \.vignetteRadius
            case .vignetteSoftness: \.vignetteSoftness
            case .grain: \.grain
            case .grainSize: \.grainSize
            case .zoom: \.zoom
            case .zoomCenterX: \.zoomCenterX
            case .zoomCenterY: \.zoomCenterY
            }
        }

        /// `value` clamped to ``range``, or neutral when it is not finite.
        public func sanitize(_ value: Double) -> Double {
            guard value.isFinite else { return 0 }
            return min(max(value, range.lowerBound), range.upperBound)
        }
    }
}
