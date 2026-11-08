// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// A pending, non-destructive color adjustment to one image.
///
/// Values are slider positions rather than Core Image parameters, so retuning the renderer's mapping
/// never changes stored data. Each is clamped to its ``Parameter/range`` on construction and on
/// assignment, a non-finite value becomes neutral, and neutral is 0 for every parameter. The renderer
/// applies them in a fixed order: exposure, temperature and tint, vibrance, highlights and shadows,
/// brightness, contrast and saturation, sepia, sharpness, vignette.
///
/// A ``bypassed`` parameter keeps its value but renders as neutral (see ``effective``).
public struct ImageAdjustmentDescription: Hashable, Sendable {
    /// Stops (EV).
    public var exposure: Double { didSet { exposure = Parameter.exposure.sanitize(exposure) } }
    public var contrast: Double { didSet { contrast = Parameter.contrast.sanitize(contrast) } }
    public var highlights: Double { didSet { highlights = Parameter.highlights.sanitize(highlights) } }
    public var shadows: Double { didSet { shadows = Parameter.shadows.sanitize(shadows) } }
    /// Moves the mid-tones and holds black and white.
    public var brightness: Double { didSet { brightness = Parameter.brightness.sanitize(brightness) } }
    public var saturation: Double { didSet { saturation = Parameter.saturation.sanitize(saturation) } }
    public var vibrance: Double { didSet { vibrance = Parameter.vibrance.sanitize(vibrance) } }
    public var temperature: Double { didSet { temperature = Parameter.temperature.sanitize(temperature) } }
    public var tint: Double { didSet { tint = Parameter.tint.sanitize(tint) } }
    public var sepia: Double { didSet { sepia = Parameter.sepia.sanitize(sepia) } }
    public var sharpness: Double { didSet { sharpness = Parameter.sharpness.sanitize(sharpness) } }
    /// Negative lightens the edges.
    public var vignette: Double { didSet { vignette = Parameter.vignette.sanitize(vignette) } }
    /// How far from the center the vignette begins. Has no effect while ``vignette`` is 0.
    public var vignetteRadius: Double { didSet { vignetteRadius = Parameter.vignetteRadius.sanitize(vignetteRadius) } }
    /// How gradual the vignette's edge is. Has no effect while ``vignette`` is 0.
    public var vignetteSoftness: Double { didSet { vignetteSoftness = Parameter.vignetteSoftness.sanitize(vignetteSoftness) } }

    /// Parameters switched off: each keeps its value and renders as neutral.
    public var bypassed: Set<Parameter>

    public init(
        exposure: Double = 0,
        contrast: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        brightness: Double = 0,
        saturation: Double = 0,
        vibrance: Double = 0,
        temperature: Double = 0,
        tint: Double = 0,
        sepia: Double = 0,
        sharpness: Double = 0,
        vignette: Double = 0,
        vignetteRadius: Double = 0,
        vignetteSoftness: Double = 0,
        bypassed: Set<Parameter> = []
    ) {
        // Property observers do not run during initialization.
        self.exposure = Parameter.exposure.sanitize(exposure)
        self.contrast = Parameter.contrast.sanitize(contrast)
        self.highlights = Parameter.highlights.sanitize(highlights)
        self.shadows = Parameter.shadows.sanitize(shadows)
        self.brightness = Parameter.brightness.sanitize(brightness)
        self.saturation = Parameter.saturation.sanitize(saturation)
        self.vibrance = Parameter.vibrance.sanitize(vibrance)
        self.temperature = Parameter.temperature.sanitize(temperature)
        self.tint = Parameter.tint.sanitize(tint)
        self.sepia = Parameter.sepia.sanitize(sepia)
        self.sharpness = Parameter.sharpness.sanitize(sharpness)
        self.vignette = Parameter.vignette.sanitize(vignette)
        self.vignetteRadius = Parameter.vignetteRadius.sanitize(vignetteRadius)
        self.vignetteSoftness = Parameter.vignetteSoftness.sanitize(vignetteSoftness)
        self.bypassed = bypassed
    }

    /// True when every parameter is neutral and none is bypassed: nothing to store. A stored
    /// adjustment in this state is represented as `nil`.
    public var isEmpty: Bool {
        bypassed.isEmpty && Parameter.allCases.allSatisfy { self[$0] == 0 }
    }

    /// What renders: every ``bypassed`` parameter at neutral, and nothing bypassed. Empty when the
    /// adjustment would leave the image unchanged.
    public var effective: ImageAdjustmentDescription {
        var result = self
        for parameter in bypassed {
            result[parameter] = 0
        }
        result.bypassed = []
        return result
    }

    /// The bypassed parameters alone, still bypassed: what stays pending once ``effective`` is
    /// rendered.
    public var bypassedPart: ImageAdjustmentDescription {
        var result = ImageAdjustmentDescription(bypassed: bypassed)
        for parameter in bypassed {
            result[parameter] = self[parameter]
        }
        return result
    }

    public subscript(parameter: Parameter) -> Double {
        get { self[keyPath: parameter.keyPath] }
        set { self[keyPath: parameter.keyPath] = newValue }
    }
}

// MARK: - Parameter

extension ImageAdjustmentDescription {
    /// Case order is display order; the renderer's order is fixed separately.
    public enum Parameter: String, CaseIterable, Codable, Sendable {
        case exposure
        case highlights
        case shadows
        case brightness
        case contrast
        case saturation
        case vibrance
        case temperature
        case tint
        case sepia
        case sharpness
        case vignette
        case vignetteRadius
        case vignetteSoftness

        /// Exposure is in stops; the rest are unitless positions. Highlights only go down: Core Image's
        /// highlight adjustment is at its maximum when neutral.
        public var range: ClosedRange<Double> {
            switch self {
            case .exposure: -3 ... 3
            case .highlights: -1 ... 0
            case .sepia, .sharpness: 0 ... 1
            case .contrast, .shadows, .brightness, .saturation, .vibrance, .temperature, .tint,
                 .vignette, .vignetteRadius, .vignetteSoftness: -1 ... 1
            }
        }

        public var keyPath: WritableKeyPath<ImageAdjustmentDescription, Double> {
            switch self {
            case .exposure: \.exposure
            case .contrast: \.contrast
            case .highlights: \.highlights
            case .shadows: \.shadows
            case .brightness: \.brightness
            case .saturation: \.saturation
            case .vibrance: \.vibrance
            case .temperature: \.temperature
            case .tint: \.tint
            case .sepia: \.sepia
            case .sharpness: \.sharpness
            case .vignette: \.vignette
            case .vignetteRadius: \.vignetteRadius
            case .vignetteSoftness: \.vignetteSoftness
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
        case exposure, contrast, highlights, shadows, brightness, saturation, vibrance, temperature, tint,
            sepia, sharpness, vignette, vignetteRadius, vignetteSoftness, bypassed
    }

    /// A missing key decodes as neutral, so data written before a parameter existed still reads. A
    /// bypassed parameter this build does not know is dropped.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            exposure: try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0,
            contrast: try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0,
            highlights: try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0,
            shadows: try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0,
            brightness: try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 0,
            saturation: try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0,
            vibrance: try c.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0,
            temperature: try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0,
            tint: try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0,
            sepia: try c.decodeIfPresent(Double.self, forKey: .sepia) ?? 0,
            sharpness: try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0,
            vignette: try c.decodeIfPresent(Double.self, forKey: .vignette) ?? 0,
            vignetteRadius: try c.decodeIfPresent(Double.self, forKey: .vignetteRadius) ?? 0,
            vignetteSoftness: try c.decodeIfPresent(Double.self, forKey: .vignetteSoftness) ?? 0,
            bypassed: Set((try c.decodeIfPresent([String].self, forKey: .bypassed) ?? []).compactMap(Parameter.init(rawValue:)))
        )
    }
}
