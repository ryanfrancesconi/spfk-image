// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import Testing

@testable import SPFKImage

@Suite
final class ImageAdjustmentDescriptionTests {
    typealias Parameter = ImageAdjustmentDescription.Parameter

    @Test func defaultDescriptionIsEmpty() {
        #expect(ImageAdjustmentDescription().isEmpty)
    }

    @Test func noArgumentInitMatchesTheFullInitializersDefaults() {
        let shared = ImageAdjustmentDescription()
        let built = ImageAdjustmentDescription(light: .init())

        #expect(shared == built)
        #expect(shared.curves.isIdentity)
        #expect(shared.bypassed.isEmpty)

        for parameter in Parameter.allCases {
            #expect(shared[parameter] == 0, "\(parameter)")
        }
    }

    @Test(arguments: Parameter.allCases)
    func anyParameterOffNeutralIsNotEmpty(parameter: Parameter) {
        var description = ImageAdjustmentDescription()
        let range = parameter.range
        description[parameter] = range.upperBound != 0 ? range.upperBound : range.lowerBound

        #expect(!description.isEmpty)
    }

    @Test(arguments: Parameter.allCases)
    func assignmentClampsEveryParameterToItsOwnRange(parameter: Parameter) {
        let range = parameter.range
        var description = ImageAdjustmentDescription()

        description[parameter] = range.upperBound + 5
        #expect(description[parameter] == range.upperBound)

        description[parameter] = range.lowerBound - 5
        #expect(description[parameter] == range.lowerBound)

        description[parameter] = .nan
        #expect(description[parameter] == 0)

        description[parameter] = .infinity
        #expect(description[parameter] == 0)
    }

    @Test func initClampsEveryParameterToItsRange() {
        let description = ImageAdjustmentDescription(
            light: .init(exposure: 99, highlights: 99, shadows: -99, contrast: -99),
            color: .init(saturation: 99, temperature: -99, tint: 99, sepia: -99),
            detail: .init(sharpness: 99)
        )

        #expect(description.light.exposure == Parameter.exposure.range.upperBound)
        #expect(description.light.contrast == Parameter.contrast.range.lowerBound)
        #expect(description.light.highlights == Parameter.highlights.range.upperBound)
        #expect(description.light.shadows == Parameter.shadows.range.lowerBound)
        #expect(description.color.saturation == Parameter.saturation.range.upperBound)
        #expect(description.color.temperature == Parameter.temperature.range.lowerBound)
        #expect(description.color.tint == Parameter.tint.range.upperBound)
        #expect(description.color.sepia == Parameter.sepia.range.lowerBound)
        #expect(description.detail.sharpness == Parameter.sharpness.range.upperBound)
    }

    @Test(arguments: ImageAdjustmentDescription.Group.allCases, [100.0, -100.0])
    func initClampsEverySection(group: ImageAdjustmentDescription.Group, value: Double) {
        let description = Self.description(holding: value, throughout: group)

        for parameter in group.parameters {
            let expected = value > 0 ? parameter.range.upperBound : parameter.range.lowerBound
            #expect(description[parameter] == expected, "\(parameter)")
        }
    }

    /// `value` in every field of `group`'s section, passed to `init` unclamped. Curves has no
    /// parameters.
    private static func description(
        holding v: Double,
        throughout group: ImageAdjustmentDescription.Group
    ) -> ImageAdjustmentDescription {
        typealias SelectiveColor = ImageAdjustmentDescription.SelectiveColor
        typealias ColorGrading = ImageAdjustmentDescription.ColorGrading

        switch group {
        case .light:
            return .init(light: .init(
                brilliance: v, exposure: v, highlights: v, shadows: v,
                brightness: v, contrast: v, blackPoint: v, whitePoint: v
            ))
        case .color:
            return .init(color: .init(saturation: v, vibrance: v, temperature: v, tint: v, sepia: v))
        case .blackAndWhite:
            return .init(blackAndWhite: .init(red: v, yellow: v, green: v, cyan: v, blue: v, magenta: v))
        case .curves:
            return .init()
        case .levels:
            return .init(levels: .init(black: v, shadow: v, mid: v, highlight: v, white: v))
        case .selectiveColor:
            let shift = SelectiveColor.Shift(hue: v, saturation: v, luminance: v, range: v)
            return .init(selectiveColor: .init(
                red: shift, yellow: shift, green: shift, cyan: shift, blue: shift, magenta: shift
            ))
        case .colorGrading:
            let tint = ColorGrading.Tint(hue: v, saturation: v)
            return .init(colorGrading: .init(shadows: tint, midtones: tint, highlights: tint, balance: v))
        case .detail:
            return .init(detail: .init(sharpness: v, sharpnessRadius: v, definition: v, noiseReduction: v))
        case .vignette:
            return .init(vignette: .init(amount: v, radius: v, softness: v))
        case .grain:
            return .init(grain: .init(amount: v, size: v))
        case .raw:
            return .init(raw: .init(colorNoiseReduction: v, moireReduction: v, lensCorrection: v))
        }
    }

    @Test func initTurnsNonFiniteValuesNeutral() {
        let description = ImageAdjustmentDescription(
            light: .init(exposure: .nan),
            color: .init(saturation: .infinity),
            detail: .init(sharpness: -.infinity)
        )

        #expect(description.isEmpty)
    }

    @Test(arguments: Parameter.allCases)
    func assignmentClampsAndRejectsNonFinite(parameter: Parameter) {
        var description = ImageAdjustmentDescription()

        description[parameter] = parameter.range.upperBound + 10
        #expect(description[parameter] == parameter.range.upperBound)

        description[parameter] = parameter.range.lowerBound - 10
        #expect(description[parameter] == parameter.range.lowerBound)

        description[parameter] = .nan
        #expect(description[parameter] == 0)
    }

    @Test func decodingClampsOutOfRangeValues() throws {
        let decoded = try decode(patching: [
            ("light", "exposure", 9),
            ("color", "sepia", -1),
            ("color", "tint", 0.25),
        ])

        #expect(decoded.light.exposure == Parameter.exposure.range.upperBound)
        #expect(decoded.color.sepia == Parameter.sepia.range.lowerBound)
        #expect(decoded.color.tint == 0.25)
    }

    @Test func codableRoundTripPreservesValues() throws {
        let original = ImageAdjustmentDescription(
            light: .init(exposure: 0.5, contrast: -0.2),
            color: .init(sepia: 0.75),
            detail: .init(sharpness: 0.1)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ImageAdjustmentDescription.self, from: data)

        #expect(decoded == original)
    }

    @Test func vibranceAndVignetteClampOnInitAndDecode() throws {
        let initialized = ImageAdjustmentDescription(color: .init(vibrance: 4), vignette: .init(amount: -4))
        #expect(initialized.color.vibrance == 1)
        #expect(initialized.vignette.amount == -1)

        let decoded = try decode(patching: [("color", "vibrance", -9), ("vignette", "amount", 9)])
        #expect(decoded.color.vibrance == -1)
        #expect(decoded.vignette.amount == 1)
    }

    /// Decodes a neutral description's encoding with each `(section, key)` replaced by its value.
    private func decode(patching patches: [(section: String, key: String, value: Double)]) throws -> ImageAdjustmentDescription {
        let encoded = try JSONEncoder().encode(ImageAdjustmentDescription())
        var json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        for patch in patches {
            var section = try #require(json[patch.section] as? [String: Any])
            section[patch.key] = patch.value
            json[patch.section] = section
        }

        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(ImageAdjustmentDescription.self, from: data)
    }
}
