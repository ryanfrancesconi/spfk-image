// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

// Each section clamps its own fields to their ``ImageAdjustmentDescription/Parameter/range``.
// Field by field rather than through `Parameter.keyPath`: a section is clamped on every assignment,
// including each column a stored row decodes into it, and a keypath read copies the whole
// description.

private func clampField(_ value: inout Double, _ parameter: ImageAdjustmentDescription.Parameter) {
    value = parameter.sanitize(value)
}

extension ImageAdjustmentDescription.Light {
    mutating func clamp() {
        clampField(&brilliance, .brilliance)
        clampField(&exposure, .exposure)
        clampField(&highlights, .highlights)
        clampField(&shadows, .shadows)
        clampField(&brightness, .brightness)
        clampField(&contrast, .contrast)
        clampField(&blackPoint, .blackPoint)
        clampField(&whitePoint, .whitePoint)
    }
}

extension ImageAdjustmentDescription.Color {
    mutating func clamp() {
        clampField(&saturation, .saturation)
        clampField(&vibrance, .vibrance)
        clampField(&temperature, .temperature)
        clampField(&tint, .tint)
        clampField(&sepia, .sepia)
    }
}

extension ImageAdjustmentDescription.BlackAndWhite {
    mutating func clamp() {
        clampField(&amount, .blackAndWhite)
        clampField(&red, ImageAdjustmentDescription.ColorBand.red.blackAndWhite)
        clampField(&yellow, ImageAdjustmentDescription.ColorBand.yellow.blackAndWhite)
        clampField(&green, ImageAdjustmentDescription.ColorBand.green.blackAndWhite)
        clampField(&cyan, ImageAdjustmentDescription.ColorBand.cyan.blackAndWhite)
        clampField(&blue, ImageAdjustmentDescription.ColorBand.blue.blackAndWhite)
        clampField(&magenta, ImageAdjustmentDescription.ColorBand.magenta.blackAndWhite)
    }
}

extension ImageAdjustmentDescription.Levels {
    mutating func clamp() {
        clampField(&black, .levelsBlack)
        clampField(&shadow, .levelsShadow)
        clampField(&mid, .levelsMid)
        clampField(&highlight, .levelsHighlight)
        clampField(&white, .levelsWhite)
    }
}

extension ImageAdjustmentDescription.SelectiveColor.Shift {
    mutating func clamp(_ band: ImageAdjustmentDescription.ColorBand) {
        clampField(&hue, band.hue)
        clampField(&saturation, band.saturation)
        clampField(&luminance, band.luminance)
    }
}

extension ImageAdjustmentDescription.SelectiveColor {
    mutating func clamp() {
        red.clamp(.red)
        yellow.clamp(.yellow)
        green.clamp(.green)
        cyan.clamp(.cyan)
        blue.clamp(.blue)
        magenta.clamp(.magenta)
    }
}

extension ImageAdjustmentDescription.ColorGrading.Tint {
    mutating func clamp(_ range: ImageAdjustmentDescription.ColorGradingRange) {
        clampField(&hue, range.hue)
        clampField(&saturation, range.saturation)
    }
}

extension ImageAdjustmentDescription.ColorGrading {
    mutating func clamp() {
        shadows.clamp(.shadows)
        midtones.clamp(.midtones)
        highlights.clamp(.highlights)
        clampField(&balance, .colorGradingBalance)
    }
}

extension ImageAdjustmentDescription.Detail {
    mutating func clamp() {
        clampField(&sharpness, .sharpness)
        clampField(&sharpnessRadius, .sharpnessRadius)
        clampField(&definition, .definition)
        clampField(&noiseReduction, .noiseReduction)
    }
}

extension ImageAdjustmentDescription.Vignette {
    mutating func clamp() {
        clampField(&amount, .vignette)
        clampField(&radius, .vignetteRadius)
        clampField(&softness, .vignetteSoftness)
    }
}

extension ImageAdjustmentDescription.Grain {
    mutating func clamp() {
        clampField(&amount, .grain)
        clampField(&size, .grainSize)
    }
}
