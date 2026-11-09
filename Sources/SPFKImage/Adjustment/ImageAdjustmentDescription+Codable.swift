// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    enum CodingKeys: String, CodingKey {
        case brilliance, exposure, contrast, highlights, shadows, brightness, blackPoint, saturation, vibrance,
            temperature, tint, sepia, levelsBlack, levelsShadow, levelsMid, levelsHighlight, levelsWhite, sharpness,
            definition, noiseReduction, vignette, vignetteRadius, vignetteSoftness, zoom, zoomCenterX, zoomCenterY, bypassed
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
            saturation: try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0,
            vibrance: try c.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0,
            temperature: try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0,
            tint: try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0,
            sepia: try c.decodeIfPresent(Double.self, forKey: .sepia) ?? 0,
            levelsBlack: try c.decodeIfPresent(Double.self, forKey: .levelsBlack) ?? 0,
            levelsShadow: try c.decodeIfPresent(Double.self, forKey: .levelsShadow) ?? 0,
            levelsMid: try c.decodeIfPresent(Double.self, forKey: .levelsMid) ?? 0,
            levelsHighlight: try c.decodeIfPresent(Double.self, forKey: .levelsHighlight) ?? 0,
            levelsWhite: try c.decodeIfPresent(Double.self, forKey: .levelsWhite) ?? 0,
            sharpness: try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0,
            definition: try c.decodeIfPresent(Double.self, forKey: .definition) ?? 0,
            noiseReduction: try c.decodeIfPresent(Double.self, forKey: .noiseReduction) ?? 0,
            vignette: try c.decodeIfPresent(Double.self, forKey: .vignette) ?? 0,
            vignetteRadius: try c.decodeIfPresent(Double.self, forKey: .vignetteRadius) ?? 0,
            vignetteSoftness: try c.decodeIfPresent(Double.self, forKey: .vignetteSoftness) ?? 0,
            zoom: try c.decodeIfPresent(Double.self, forKey: .zoom) ?? 0,
            zoomCenterX: try c.decodeIfPresent(Double.self, forKey: .zoomCenterX) ?? 0,
            zoomCenterY: try c.decodeIfPresent(Double.self, forKey: .zoomCenterY) ?? 0,
            bypassed: Set((try c.decodeIfPresent([String].self, forKey: .bypassed) ?? []).compactMap(Parameter.init(rawValue:)))
        )
    }
}
