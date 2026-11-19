// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// A pending, non-destructive color adjustment to one image, one value per section of the Adjust tab.
///
/// Values are slider positions rather than Core Image parameters, so retuning the renderer's mapping
/// never changes stored data. Each is clamped to its ``Parameter/range`` on construction, decoding and
/// assignment, a non-finite value becomes neutral, and neutral is 0 for every parameter. The renderer
/// applies them in a fixed order, the case order of its internal `RenderStep`.
///
/// A ``bypassed`` section keeps its values but renders as neutral (see ``effective``).
public struct ImageAdjustmentDescription: Hashable, Sendable, Codable {
    public var light: Light { didSet { light.clamp() } }
    public var color: Color { didSet { color.clamp() } }
    public var blackAndWhite: BlackAndWhite { didSet { blackAndWhite.clamp() } }
    /// Applied after levels.
    public var curves: ImageToneCurves
    public var levels: Levels { didSet { levels.clamp() } }
    public var selectiveColor: SelectiveColor { didSet { selectiveColor.clamp() } }
    public var colorGrading: ColorGrading { didSet { colorGrading.clamp() } }
    public var detail: Detail { didSet { detail.clamp() } }
    public var vignette: Vignette { didSet { vignette.clamp() } }
    public var grain: Grain { didSet { grain.clamp() } }

    /// Sections switched off: each keeps its values and renders as neutral.
    public var bypassed: Set<Group>

    /// Every section neutral and nothing bypassed. One shared value: building it clamps every
    /// parameter, which a per-row caller cannot afford.
    public init() {
        self = Self.neutral
    }

    private static let neutral = ImageAdjustmentDescription(light: Light())

    public init(
        light: Light = Light(),
        color: Color = Color(),
        blackAndWhite: BlackAndWhite = BlackAndWhite(),
        curves: ImageToneCurves = .identity,
        levels: Levels = Levels(),
        selectiveColor: SelectiveColor = SelectiveColor(),
        colorGrading: ColorGrading = ColorGrading(),
        detail: Detail = Detail(),
        vignette: Vignette = Vignette(),
        grain: Grain = Grain(),
        bypassed: Set<Group> = []
    ) {
        self.light = light
        self.color = color
        self.blackAndWhite = blackAndWhite
        self.curves = curves
        self.levels = levels
        self.selectiveColor = selectiveColor
        self.colorGrading = colorGrading
        self.detail = detail
        self.vignette = vignette
        self.grain = grain
        self.bypassed = bypassed

        // Observers do not run in `init`.
        self.light.clamp()
        self.color.clamp()
        self.blackAndWhite.clamp()
        self.levels.clamp()
        self.selectiveColor.clamp()
        self.colorGrading.clamp()
        self.detail.clamp()
        self.vignette.clamp()
        self.grain.clamp()
    }

    /// Decodes through ``init(light:color:blackAndWhite:curves:levels:selectiveColor:colorGrading:detail:vignette:grain:bypassed:)``,
    /// so a decoded value is clamped as an assigned one is.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        try self.init(
            light: c.decode(Light.self, forKey: .light),
            color: c.decode(Color.self, forKey: .color),
            blackAndWhite: c.decode(BlackAndWhite.self, forKey: .blackAndWhite),
            curves: c.decode(ImageToneCurves.self, forKey: .curves),
            levels: c.decode(Levels.self, forKey: .levels),
            selectiveColor: c.decode(SelectiveColor.self, forKey: .selectiveColor),
            colorGrading: c.decode(ColorGrading.self, forKey: .colorGrading),
            detail: c.decode(Detail.self, forKey: .detail),
            vignette: c.decode(Vignette.self, forKey: .vignette),
            grain: c.decode(Grain.self, forKey: .grain),
            bypassed: c.decode(Set<Group>.self, forKey: .bypassed)
        )
    }

    /// True when every parameter is neutral, the curves are identity, and nothing is bypassed: nothing
    /// to store. A stored adjustment in this state is represented as `nil`.
    public var isEmpty: Bool {
        self == Self.neutral
    }

    /// Whether every value in `group` is neutral.
    public func isNeutral(_ group: Group) -> Bool {
        switch group {
        case .light: light.isNeutral
        case .color: color.isNeutral
        case .blackAndWhite: blackAndWhite.isNeutral
        case .curves: curves.isIdentity
        case .levels: levels.isNeutral
        case .selectiveColor: selectiveColor.isNeutral
        case .colorGrading: colorGrading.isNeutral
        case .detail: detail.isNeutral
        case .vignette: vignette.isNeutral
        case .grain: grain.isNeutral
        }
    }

    /// What renders: every ``bypassed`` section at neutral, and nothing bypassed. Empty when the
    /// adjustment would leave the image unchanged.
    public var effective: ImageAdjustmentDescription {
        var result = self
        for group in bypassed {
            result.reset(group)
        }
        result.bypassed = []
        return result
    }

    /// The bypassed sections, still bypassed: what stays pending once ``effective`` is rendered.
    public var bypassedPart: ImageAdjustmentDescription {
        var result = ImageAdjustmentDescription()
        for group in bypassed {
            result.take(group, from: self)
        }
        result.bypassed = bypassed
        return result
    }

    /// Returns `group` to neutral. Whether it is bypassed is unchanged.
    public mutating func reset(_ group: Group) {
        take(group, from: ImageAdjustmentDescription())
    }

    /// Replaces `group`'s values with `other`'s. Whether it is bypassed is unchanged.
    public mutating func take(_ group: Group, from other: ImageAdjustmentDescription) {
        switch group {
        case .light: light = other.light
        case .color: color = other.color
        case .blackAndWhite: blackAndWhite = other.blackAndWhite
        case .curves: curves = other.curves
        case .levels: levels = other.levels
        case .selectiveColor: selectiveColor = other.selectiveColor
        case .colorGrading: colorGrading = other.colorGrading
        case .detail: detail = other.detail
        case .vignette: vignette = other.vignette
        case .grain: grain = other.grain
        }
    }

    public subscript(parameter: Parameter) -> Double {
        get { self[keyPath: parameter.keyPath] }
        set { self[keyPath: parameter.keyPath] = newValue }
    }
}
