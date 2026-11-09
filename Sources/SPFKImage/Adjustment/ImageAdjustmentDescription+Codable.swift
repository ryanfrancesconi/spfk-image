// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    enum CodingKeys: String, CodingKey {
        case brilliance, exposure, contrast, highlights, shadows, brightness, blackPoint, whitePoint, saturation, vibrance,
            temperature, tint, sepia, blackAndWhite, blackAndWhiteRed, blackAndWhiteGreen, blackAndWhiteBlue, levelsBlack, levelsShadow, levelsMid, levelsHighlight, levelsWhite,
            selectiveRedHue, selectiveRedSaturation, selectiveRedLuminance,
            selectiveYellowHue, selectiveYellowSaturation, selectiveYellowLuminance,
            selectiveGreenHue, selectiveGreenSaturation, selectiveGreenLuminance,
            selectiveCyanHue, selectiveCyanSaturation, selectiveCyanLuminance,
            selectiveBlueHue, selectiveBlueSaturation, selectiveBlueLuminance,
            selectiveMagentaHue, selectiveMagentaSaturation, selectiveMagentaLuminance,
            sharpness, sharpnessRadius, definition, noiseReduction, vignette, vignetteRadius, vignetteSoftness, zoom, zoomCenterX, zoomCenterY, bypassed,
            curves, curvesBypassed
    }

    /// A missing key decodes as neutral, so data written before a parameter existed still reads. A
    /// bypassed parameter this build does not know is dropped.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            brilliance: try c.decodeIfPresent(Double.self, forKey: .brilliance) ?? 0,
            exposure: try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0,
            contrast: try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0,
            highlights: try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0,
            shadows: try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0,
            brightness: try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 0,
            blackPoint: try c.decodeIfPresent(Double.self, forKey: .blackPoint) ?? 0,
            whitePoint: try c.decodeIfPresent(Double.self, forKey: .whitePoint) ?? 0,
            saturation: try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0,
            vibrance: try c.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0,
            temperature: try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0,
            tint: try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0,
            sepia: try c.decodeIfPresent(Double.self, forKey: .sepia) ?? 0,
            blackAndWhite: try c.decodeIfPresent(Double.self, forKey: .blackAndWhite) ?? 0,
            blackAndWhiteRed: try c.decodeIfPresent(Double.self, forKey: .blackAndWhiteRed) ?? 0,
            blackAndWhiteGreen: try c.decodeIfPresent(Double.self, forKey: .blackAndWhiteGreen) ?? 0,
            blackAndWhiteBlue: try c.decodeIfPresent(Double.self, forKey: .blackAndWhiteBlue) ?? 0,
            levelsBlack: try c.decodeIfPresent(Double.self, forKey: .levelsBlack) ?? 0,
            levelsShadow: try c.decodeIfPresent(Double.self, forKey: .levelsShadow) ?? 0,
            levelsMid: try c.decodeIfPresent(Double.self, forKey: .levelsMid) ?? 0,
            levelsHighlight: try c.decodeIfPresent(Double.self, forKey: .levelsHighlight) ?? 0,
            levelsWhite: try c.decodeIfPresent(Double.self, forKey: .levelsWhite) ?? 0,
            selectiveRedHue: try c.decodeIfPresent(Double.self, forKey: .selectiveRedHue) ?? 0,
            selectiveRedSaturation: try c.decodeIfPresent(Double.self, forKey: .selectiveRedSaturation) ?? 0,
            selectiveRedLuminance: try c.decodeIfPresent(Double.self, forKey: .selectiveRedLuminance) ?? 0,
            selectiveYellowHue: try c.decodeIfPresent(Double.self, forKey: .selectiveYellowHue) ?? 0,
            selectiveYellowSaturation: try c.decodeIfPresent(Double.self, forKey: .selectiveYellowSaturation) ?? 0,
            selectiveYellowLuminance: try c.decodeIfPresent(Double.self, forKey: .selectiveYellowLuminance) ?? 0,
            selectiveGreenHue: try c.decodeIfPresent(Double.self, forKey: .selectiveGreenHue) ?? 0,
            selectiveGreenSaturation: try c.decodeIfPresent(Double.self, forKey: .selectiveGreenSaturation) ?? 0,
            selectiveGreenLuminance: try c.decodeIfPresent(Double.self, forKey: .selectiveGreenLuminance) ?? 0,
            selectiveCyanHue: try c.decodeIfPresent(Double.self, forKey: .selectiveCyanHue) ?? 0,
            selectiveCyanSaturation: try c.decodeIfPresent(Double.self, forKey: .selectiveCyanSaturation) ?? 0,
            selectiveCyanLuminance: try c.decodeIfPresent(Double.self, forKey: .selectiveCyanLuminance) ?? 0,
            selectiveBlueHue: try c.decodeIfPresent(Double.self, forKey: .selectiveBlueHue) ?? 0,
            selectiveBlueSaturation: try c.decodeIfPresent(Double.self, forKey: .selectiveBlueSaturation) ?? 0,
            selectiveBlueLuminance: try c.decodeIfPresent(Double.self, forKey: .selectiveBlueLuminance) ?? 0,
            selectiveMagentaHue: try c.decodeIfPresent(Double.self, forKey: .selectiveMagentaHue) ?? 0,
            selectiveMagentaSaturation: try c.decodeIfPresent(Double.self, forKey: .selectiveMagentaSaturation) ?? 0,
            selectiveMagentaLuminance: try c.decodeIfPresent(Double.self, forKey: .selectiveMagentaLuminance) ?? 0,
            sharpness: try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0,
            sharpnessRadius: try c.decodeIfPresent(Double.self, forKey: .sharpnessRadius) ?? 0,
            definition: try c.decodeIfPresent(Double.self, forKey: .definition) ?? 0,
            noiseReduction: try c.decodeIfPresent(Double.self, forKey: .noiseReduction) ?? 0,
            vignette: try c.decodeIfPresent(Double.self, forKey: .vignette) ?? 0,
            vignetteRadius: try c.decodeIfPresent(Double.self, forKey: .vignetteRadius) ?? 0,
            vignetteSoftness: try c.decodeIfPresent(Double.self, forKey: .vignetteSoftness) ?? 0,
            zoom: try c.decodeIfPresent(Double.self, forKey: .zoom) ?? 0,
            zoomCenterX: try c.decodeIfPresent(Double.self, forKey: .zoomCenterX) ?? 0,
            zoomCenterY: try c.decodeIfPresent(Double.self, forKey: .zoomCenterY) ?? 0,
            bypassed: Set((try c.decodeIfPresent([String].self, forKey: .bypassed) ?? []).compactMap(Parameter.init(rawValue:))),
            curves: try c.decodeIfPresent(ImageToneCurves.self, forKey: .curves) ?? .identity,
            curvesBypassed: try c.decodeIfPresent(Bool.self, forKey: .curvesBypassed) ?? false
        )
    }
}
