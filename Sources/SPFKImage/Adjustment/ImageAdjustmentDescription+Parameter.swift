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
        case saturation
        case vibrance
        case temperature
        case tint
        case sepia
        case levelsBlack
        case levelsShadow
        case levelsMid
        case levelsHighlight
        case levelsWhite
        case sharpness
        case definition
        case noiseReduction
        case vignette
        case vignetteRadius
        case vignetteSoftness

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
            case .sepia, .sharpness, .definition, .noiseReduction, .levelsBlack, .zoom: 0 ... 1
            case .zoomCenterX, .zoomCenterY: -0.5 ... 0.5
            case .levelsShadow: -0.25 ... 0.75
            case .levelsMid: -0.5 ... 0.5
            case .levelsHighlight: -0.75 ... 0.25
            case .levelsWhite: -1 ... 0
            case .brilliance, .contrast, .shadows, .brightness, .blackPoint, .saturation, .vibrance, .temperature, .tint,
                 .vignette, .vignetteRadius, .vignetteSoftness: -1 ... 1
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
            case .saturation: \.saturation
            case .vibrance: \.vibrance
            case .temperature: \.temperature
            case .tint: \.tint
            case .sepia: \.sepia
            case .levelsBlack: \.levelsBlack
            case .levelsShadow: \.levelsShadow
            case .levelsMid: \.levelsMid
            case .levelsHighlight: \.levelsHighlight
            case .levelsWhite: \.levelsWhite
            case .sharpness: \.sharpness
            case .definition: \.definition
            case .noiseReduction: \.noiseReduction
            case .vignette: \.vignette
            case .vignetteRadius: \.vignetteRadius
            case .vignetteSoftness: \.vignetteSoftness
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
