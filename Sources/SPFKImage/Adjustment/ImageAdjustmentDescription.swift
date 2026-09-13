// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// A pending, non-destructive color adjustment to one image.
///
/// Values are slider positions rather than Core Image parameters, so retuning the renderer's mapping
/// never changes stored data. Each is clamped to its ``Parameter/range`` on construction and on
/// assignment, a non-finite value becomes neutral, and neutral is 0 for every parameter. The renderer
/// applies them in a fixed order: exposure, temperature and tint, highlights and shadows, contrast and
/// saturation, sepia, sharpness.
public struct ImageAdjustmentDescription: Hashable, Sendable {
    /// Stops (EV).
    public var exposure: Double { didSet { exposure = Parameter.exposure.sanitize(exposure) } }
    public var contrast: Double { didSet { contrast = Parameter.contrast.sanitize(contrast) } }
    public var highlights: Double { didSet { highlights = Parameter.highlights.sanitize(highlights) } }
    public var shadows: Double { didSet { shadows = Parameter.shadows.sanitize(shadows) } }
    public var saturation: Double { didSet { saturation = Parameter.saturation.sanitize(saturation) } }
    public var temperature: Double { didSet { temperature = Parameter.temperature.sanitize(temperature) } }
    public var tint: Double { didSet { tint = Parameter.tint.sanitize(tint) } }
    public var sepia: Double { didSet { sepia = Parameter.sepia.sanitize(sepia) } }
    public var sharpness: Double { didSet { sharpness = Parameter.sharpness.sanitize(sharpness) } }

    public init(
        exposure: Double = 0,
        contrast: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        saturation: Double = 0,
        temperature: Double = 0,
        tint: Double = 0,
        sepia: Double = 0,
        sharpness: Double = 0
    ) {
        // Property observers do not run during initialization.
        self.exposure = Parameter.exposure.sanitize(exposure)
        self.contrast = Parameter.contrast.sanitize(contrast)
        self.highlights = Parameter.highlights.sanitize(highlights)
        self.shadows = Parameter.shadows.sanitize(shadows)
        self.saturation = Parameter.saturation.sanitize(saturation)
        self.temperature = Parameter.temperature.sanitize(temperature)
        self.tint = Parameter.tint.sanitize(tint)
        self.sepia = Parameter.sepia.sanitize(sepia)
        self.sharpness = Parameter.sharpness.sanitize(sharpness)
    }

    /// True when every parameter is neutral. A stored adjustment in this state is represented as `nil`.
    public var isEmpty: Bool {
        Parameter.allCases.allSatisfy { self[$0] == 0 }
    }

    public subscript(parameter: Parameter) -> Double {
        get { self[keyPath: parameter.keyPath] }
        set { self[keyPath: parameter.keyPath] = newValue }
    }
}

// MARK: - Parameter

extension ImageAdjustmentDescription {
    public enum Parameter: String, CaseIterable, Sendable {
        case exposure
        case contrast
        case highlights
        case shadows
        case saturation
        case temperature
        case tint
        case sepia
        case sharpness

        /// Exposure is in stops; the rest are unitless positions. Highlights only go down: Core Image's
        /// highlight adjustment is at its maximum when neutral.
        public var range: ClosedRange<Double> {
            switch self {
            case .exposure: -3 ... 3
            case .highlights: -1 ... 0
            case .sepia, .sharpness: 0 ... 1
            case .contrast, .shadows, .saturation, .temperature, .tint: -1 ... 1
            }
        }

        public var keyPath: WritableKeyPath<ImageAdjustmentDescription, Double> {
            switch self {
            case .exposure: \.exposure
            case .contrast: \.contrast
            case .highlights: \.highlights
            case .shadows: \.shadows
            case .saturation: \.saturation
            case .temperature: \.temperature
            case .tint: \.tint
            case .sepia: \.sepia
            case .sharpness: \.sharpness
            }
        }

        /// `value` clamped to ``range``, or neutral when it is not finite.
        public func sanitize(_ value: Double) -> Double {
            guard value.isFinite else { return 0 }
            return min(max(value, range.lowerBound), range.upperBound)
        }
    }
}

// MARK: - Codable

extension ImageAdjustmentDescription: Codable {
    private enum CodingKeys: String, CodingKey {
        case exposure, contrast, highlights, shadows, saturation, temperature, tint, sepia, sharpness
    }

    /// A missing key decodes as neutral, so data written before a parameter existed still reads.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            exposure: try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0,
            contrast: try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0,
            highlights: try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0,
            shadows: try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0,
            saturation: try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0,
            temperature: try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0,
            tint: try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0,
            sepia: try c.decodeIfPresent(Double.self, forKey: .sepia) ?? 0,
            sharpness: try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
        )
    }
}
