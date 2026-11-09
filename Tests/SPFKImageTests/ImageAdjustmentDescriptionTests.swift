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

    @Test(arguments: Parameter.allCases)
    func anyParameterOffNeutralIsNotEmpty(parameter: Parameter) {
        var description = ImageAdjustmentDescription()
        let range = parameter.range
        description[parameter] = range.upperBound != 0 ? range.upperBound : range.lowerBound

        #expect(!description.isEmpty)
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
