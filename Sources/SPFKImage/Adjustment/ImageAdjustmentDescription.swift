// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// A pending, non-destructive color adjustment to one image.
///
/// Values are slider positions rather than Core Image parameters, so retuning the renderer's mapping
/// never changes stored data. Each is clamped to its ``Parameter/range`` on construction and on
/// assignment, a non-finite value becomes neutral, and neutral is 0 for every parameter. The renderer
/// applies them in a fixed order: noise reduction, exposure, temperature and tint, vibrance, black point, white point, levels,
/// highlights and shadows, brightness, brilliance, contrast and saturation, definition, sepia,
/// sharpness, vignette.
///
/// A ``bypassed`` parameter keeps its value but renders as neutral (see ``effective``). The
/// ``Parameter/isViewState`` parameters describe how the preview shows the image, not an edit, and
/// never render.
public struct ImageAdjustmentDescription: Hashable, Sendable, Codable {
    /// Positive lifts shadows and holds highlights, region by region; negative deepens both.
    public var brilliance: Double { didSet { brilliance = Parameter.brilliance.sanitize(brilliance) } }
    /// Stops (EV).
    public var exposure: Double { didSet { exposure = Parameter.exposure.sanitize(exposure) } }
    public var contrast: Double { didSet { contrast = Parameter.contrast.sanitize(contrast) } }
    public var highlights: Double { didSet { highlights = Parameter.highlights.sanitize(highlights) } }
    public var shadows: Double { didSet { shadows = Parameter.shadows.sanitize(shadows) } }
    /// Moves the mid-tones and holds black and white.
    public var brightness: Double { didSet { brightness = Parameter.brightness.sanitize(brightness) } }
    /// Positive crushes the darkest tones to black; negative lifts black to a gray floor.
    public var blackPoint: Double { didSet { blackPoint = Parameter.blackPoint.sanitize(blackPoint) } }
    /// Positive clips the brightest tones to white; negative lowers white to a gray ceiling.
    public var whitePoint: Double { didSet { whitePoint = Parameter.whitePoint.sanitize(whitePoint) } }
    public var saturation: Double { didSet { saturation = Parameter.saturation.sanitize(saturation) } }
    public var vibrance: Double { didSet { vibrance = Parameter.vibrance.sanitize(vibrance) } }
    public var temperature: Double { didSet { temperature = Parameter.temperature.sanitize(temperature) } }
    public var tint: Double { didSet { tint = Parameter.tint.sanitize(tint) } }
    public var sepia: Double { didSet { sepia = Parameter.sepia.sanitize(sepia) } }
    /// Levels: how far each curve point's input sits from its identity position (see
    /// ``levelsPositions``).
    public var levelsBlack: Double { didSet { levelsBlack = Parameter.levelsBlack.sanitize(levelsBlack) } }
    public var levelsShadow: Double { didSet { levelsShadow = Parameter.levelsShadow.sanitize(levelsShadow) } }
    public var levelsMid: Double { didSet { levelsMid = Parameter.levelsMid.sanitize(levelsMid) } }
    public var levelsHighlight: Double { didSet { levelsHighlight = Parameter.levelsHighlight.sanitize(levelsHighlight) } }
    public var levelsWhite: Double { didSet { levelsWhite = Parameter.levelsWhite.sanitize(levelsWhite) } }
    public var sharpness: Double { didSet { sharpness = Parameter.sharpness.sanitize(sharpness) } }
    /// How wide an edge sharpening reaches. Has no effect while ``sharpness`` is 0.
    public var sharpnessRadius: Double { didSet { sharpnessRadius = Parameter.sharpnessRadius.sanitize(sharpnessRadius) } }
    /// Local contrast: strengthens detail against its surroundings without halos at strong edges.
    public var definition: Double { didSet { definition = Parameter.definition.sanitize(definition) } }
    public var noiseReduction: Double { didSet { noiseReduction = Parameter.noiseReduction.sanitize(noiseReduction) } }
    /// Negative lightens the edges.
    public var vignette: Double { didSet { vignette = Parameter.vignette.sanitize(vignette) } }
    /// How far from the center the vignette begins. Has no effect while ``vignette`` is 0.
    public var vignetteRadius: Double { didSet { vignetteRadius = Parameter.vignetteRadius.sanitize(vignetteRadius) } }
    /// How gradual the vignette's edge is. Has no effect while ``vignette`` is 0.
    public var vignetteSoftness: Double { didSet { vignetteSoftness = Parameter.vignetteSoftness.sanitize(vignetteSoftness) } }
    /// The preview's zoom: 0 fits the view, 1 is the largest. View state.
    public var zoom: Double { didSet { zoom = Parameter.zoom.sanitize(zoom) } }
    /// Where the zoomed preview is centered, as an offset from the image's center in fractions of its
    /// width and height; right and down are positive. View state, with no effect while ``zoom`` is 0.
    public var zoomCenterX: Double { didSet { zoomCenterX = Parameter.zoomCenterX.sanitize(zoomCenterX) } }
    public var zoomCenterY: Double { didSet { zoomCenterY = Parameter.zoomCenterY.sanitize(zoomCenterY) } }

    /// Parameters switched off: each keeps its value and renders as neutral.
    public var bypassed: Set<Parameter>

    public init(
        brilliance: Double = 0,
        exposure: Double = 0,
        contrast: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        brightness: Double = 0,
        blackPoint: Double = 0,
        whitePoint: Double = 0,
        saturation: Double = 0,
        vibrance: Double = 0,
        temperature: Double = 0,
        tint: Double = 0,
        sepia: Double = 0,
        levelsBlack: Double = 0,
        levelsShadow: Double = 0,
        levelsMid: Double = 0,
        levelsHighlight: Double = 0,
        levelsWhite: Double = 0,
        sharpness: Double = 0,
        sharpnessRadius: Double = 0,
        definition: Double = 0,
        noiseReduction: Double = 0,
        vignette: Double = 0,
        vignetteRadius: Double = 0,
        vignetteSoftness: Double = 0,
        zoom: Double = 0,
        zoomCenterX: Double = 0,
        zoomCenterY: Double = 0,
        bypassed: Set<Parameter> = []
    ) {
        // Property observers do not run during initialization.
        self.brilliance = Parameter.brilliance.sanitize(brilliance)
        self.exposure = Parameter.exposure.sanitize(exposure)
        self.contrast = Parameter.contrast.sanitize(contrast)
        self.highlights = Parameter.highlights.sanitize(highlights)
        self.shadows = Parameter.shadows.sanitize(shadows)
        self.brightness = Parameter.brightness.sanitize(brightness)
        self.blackPoint = Parameter.blackPoint.sanitize(blackPoint)
        self.whitePoint = Parameter.whitePoint.sanitize(whitePoint)
        self.saturation = Parameter.saturation.sanitize(saturation)
        self.vibrance = Parameter.vibrance.sanitize(vibrance)
        self.temperature = Parameter.temperature.sanitize(temperature)
        self.tint = Parameter.tint.sanitize(tint)
        self.sepia = Parameter.sepia.sanitize(sepia)
        self.levelsBlack = Parameter.levelsBlack.sanitize(levelsBlack)
        self.levelsShadow = Parameter.levelsShadow.sanitize(levelsShadow)
        self.levelsMid = Parameter.levelsMid.sanitize(levelsMid)
        self.levelsHighlight = Parameter.levelsHighlight.sanitize(levelsHighlight)
        self.levelsWhite = Parameter.levelsWhite.sanitize(levelsWhite)
        self.sharpness = Parameter.sharpness.sanitize(sharpness)
        self.sharpnessRadius = Parameter.sharpnessRadius.sanitize(sharpnessRadius)
        self.definition = Parameter.definition.sanitize(definition)
        self.noiseReduction = Parameter.noiseReduction.sanitize(noiseReduction)
        self.vignette = Parameter.vignette.sanitize(vignette)
        self.vignetteRadius = Parameter.vignetteRadius.sanitize(vignetteRadius)
        self.vignetteSoftness = Parameter.vignetteSoftness.sanitize(vignetteSoftness)
        self.zoom = Parameter.zoom.sanitize(zoom)
        self.zoomCenterX = Parameter.zoomCenterX.sanitize(zoomCenterX)
        self.zoomCenterY = Parameter.zoomCenterY.sanitize(zoomCenterY)
        self.bypassed = bypassed
    }

    /// True when every parameter is neutral and none is bypassed: nothing to store. A stored
    /// adjustment in this state is represented as `nil`.
    public var isEmpty: Bool {
        bypassed.isEmpty && Parameter.allCases.allSatisfy { self[$0] == 0 }
    }

    /// What renders: every ``bypassed`` and view-state parameter at neutral, and nothing bypassed.
    /// Empty when the adjustment would leave the image unchanged.
    public var effective: ImageAdjustmentDescription {
        var result = withoutViewState
        for parameter in bypassed {
            result[parameter] = 0
        }
        result.bypassed = []
        return result
    }

    /// The bypassed parameters, still bypassed, and the view state: what stays pending once
    /// ``effective`` is rendered.
    public var unrenderedPart: ImageAdjustmentDescription {
        var result = viewState
        result.bypassed = bypassed
        for parameter in bypassed {
            result[parameter] = self[parameter]
        }
        return result
    }

    /// The edit alone, with the view state at neutral.
    public var withoutViewState: ImageAdjustmentDescription {
        var result = self
        for parameter in Parameter.viewState {
            result[parameter] = 0
        }
        return result
    }

    /// The view state alone.
    public var viewState: ImageAdjustmentDescription {
        var result = ImageAdjustmentDescription()
        for parameter in Parameter.viewState {
            result[parameter] = self[parameter]
        }
        return result
    }

    /// This edit with `other`'s view state.
    public func keepingViewState(of other: ImageAdjustmentDescription) -> ImageAdjustmentDescription {
        var result = self
        for parameter in Parameter.viewState {
            result[parameter] = other[parameter]
        }
        return result
    }

    public subscript(parameter: Parameter) -> Double {
        get { self[keyPath: parameter.keyPath] }
        set { self[keyPath: parameter.keyPath] = newValue }
    }
}
