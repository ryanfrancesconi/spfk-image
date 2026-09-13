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
            exposure: 99, contrast: -99, highlights: 99, shadows: -99, saturation: 99,
            temperature: -99, tint: 99, sepia: -99, sharpness: 99
        )

        #expect(description.exposure == Parameter.exposure.range.upperBound)
        #expect(description.contrast == Parameter.contrast.range.lowerBound)
        #expect(description.highlights == Parameter.highlights.range.upperBound)
        #expect(description.shadows == Parameter.shadows.range.lowerBound)
        #expect(description.saturation == Parameter.saturation.range.upperBound)
        #expect(description.temperature == Parameter.temperature.range.lowerBound)
        #expect(description.tint == Parameter.tint.range.upperBound)
        #expect(description.sepia == Parameter.sepia.range.lowerBound)
        #expect(description.sharpness == Parameter.sharpness.range.upperBound)
    }

    @Test func initTurnsNonFiniteValuesNeutral() {
        let description = ImageAdjustmentDescription(exposure: .nan, saturation: .infinity, sharpness: -.infinity)

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

    @Test func decodingAnEmptyObjectYieldsNeutral() throws {
        let decoded = try JSONDecoder().decode(ImageAdjustmentDescription.self, from: Data("{}".utf8))

        #expect(decoded.isEmpty)
    }

    @Test func decodingClampsOutOfRangeValues() throws {
        let json = #"{"exposure": 9, "sepia": -1, "tint": 0.25}"#
        let decoded = try JSONDecoder().decode(ImageAdjustmentDescription.self, from: Data(json.utf8))

        #expect(decoded.exposure == Parameter.exposure.range.upperBound)
        #expect(decoded.sepia == Parameter.sepia.range.lowerBound)
        #expect(decoded.tint == 0.25)
    }

    @Test func codableRoundTripPreservesValues() throws {
        let original = ImageAdjustmentDescription(exposure: 0.5, contrast: -0.2, sepia: 0.75, sharpness: 0.1)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ImageAdjustmentDescription.self, from: data)

        #expect(decoded == original)
    }
}
