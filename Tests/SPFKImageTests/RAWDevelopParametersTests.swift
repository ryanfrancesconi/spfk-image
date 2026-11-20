// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKTesting
import Testing

@testable import SPFKImage

/// The mapping from slider positions to `CIRAWFilter`'s values, and what it leaves for the renderer.
@Suite(.tags(.rawDevelop))
struct RAWDevelopParametersTests {
    private typealias Parameters = RAWDevelop.Parameters

    private func parameters(
        _ adjustments: ImageAdjustmentDescription,
        asShotTemperature: Double = 5000,
        asShotTint: Double = 10,
        supportsNoiseReduction: Bool = true
    ) -> Parameters {
        Parameters(
            adjustments,
            asShotTemperature: asShotTemperature,
            asShotTint: asShotTint,
            supportsLuminanceNoiseReduction: supportsNoiseReduction
        )
    }

    private func color(temperature: Double = 0, tint: Double = 0) -> ImageAdjustmentDescription {
        ImageAdjustmentDescription(color: .init(temperature: temperature, tint: tint))
    }

    @Test func aNeutralDescriptionSetsNothing() {
        let result = parameters(ImageAdjustmentDescription())

        #expect(result.exposure == 0)
        #expect(result.neutralTemperature == nil)
        #expect(result.neutralTint == nil)
        #expect(result.luminanceNoiseReduction == nil)
        #expect(result.remaining.isEmpty)
    }

    @Test func exposurePassesThroughInStops() {
        let result = parameters(ImageAdjustmentDescription(light: .init(exposure: -1.5)))

        #expect(result.exposure == -1.5)
        #expect(result.remaining.isEmpty)
    }

    @Test func temperatureMovesTheAsShotWhiteInMired() throws {
        let result = parameters(color(temperature: 1), asShotTemperature: 5000, asShotTint: 10)
        let expected: Double = 1_000_000 / (200 - 80)

        let temperature = try #require(result.neutralTemperature)
        #expect(abs(temperature - expected) < 1e-9)
        #expect(result.neutralTint == 10)
        #expect(result.remaining.isEmpty)
    }

    @Test func temperatureIsLimitedToTheMiredRange() throws {
        let hot = parameters(color(temperature: 1), asShotTemperature: 20000)
        let cold = parameters(color(temperature: -1), asShotTemperature: 2100)

        let hotKelvin = 1_000_000 / RAWDevelop.minimumMired
        let coldKelvin = 1_000_000 / RAWDevelop.maximumMired

        #expect(try abs(#require(hot.neutralTemperature) - hotKelvin) < 1e-9)
        #expect(try abs(#require(cold.neutralTemperature) - coldKelvin) < 1e-9)
    }

    @Test func fullTintMovesTheAsShotTintByTheWhiteBalanceOffsets() throws {
        let magenta = parameters(color(tint: 1), asShotTint: 10)
        let green = parameters(color(tint: -1), asShotTint: 10)

        let magentaShift = WhiteBalanceStep.maximumMagentaTintOffset * RAWDevelop.tintPerUVOffset
        let greenShift = WhiteBalanceStep.maximumGreenTintOffset * RAWDevelop.tintPerUVOffset

        #expect(try abs(#require(magenta.neutralTint) - (10 + magentaShift)) < 1e-9)
        #expect(try abs(#require(green.neutralTint) - (10 - greenShift)) < 1e-9)
    }

    @Test func tintAloneKeepsTheAsShotTemperature() {
        let result = parameters(color(tint: 0.5), asShotTemperature: 4321, asShotTint: 3)

        #expect(result.neutralTemperature == 4321)
        #expect(result.neutralTint != nil)
        #expect(result.remaining.isEmpty)
    }

    @Test func noiseReductionIsTakenOnlyWhenTheFileSupportsIt() {
        let description = ImageAdjustmentDescription(detail: .init(noiseReduction: 0.7))

        let supported = parameters(description, supportsNoiseReduction: true)
        #expect(supported.luminanceNoiseReduction == 0.7)
        #expect(supported.remaining.isEmpty)

        let unsupported = parameters(description, supportsNoiseReduction: false)
        #expect(unsupported.luminanceNoiseReduction == nil)
        #expect(unsupported.remaining.detail.noiseReduction == 0.7)
    }

    @Test func aBypassedSectionContributesNothing() {
        let description = ImageAdjustmentDescription(light: .init(exposure: 2), bypassed: [.light])
        let result = parameters(description)

        #expect(result.exposure == 0)
        #expect(result.remaining.bypassed.isEmpty)
        #expect(result.remaining.isEmpty)
    }

    @Test func valuesTheDevelopDoesNotTakeRemain() {
        var description = ImageAdjustmentDescription(light: .init(exposure: 1))
        description[.contrast] = 0.4
        description[.vignette] = 0.6
        description.curves.rgb = [.init(x: 0, y: 0), .init(x: 0.5, y: 0.6), .init(x: 1, y: 1)]

        let result = parameters(description)

        var expected = description
        expected.light.exposure = 0
        #expect(result.remaining == expected)
    }

    @Test func takesAnyIsTrueOnlyForAValueTheDevelopTakes() {
        var description = ImageAdjustmentDescription()
        description[.contrast] = 0.4
        #expect(!RAWDevelop.takesAny(of: description))

        description[.tint] = 0.2
        #expect(RAWDevelop.takesAny(of: description))

        description.bypassed = [.color]
        #expect(!RAWDevelop.takesAny(of: description))

        #expect(RAWDevelop.takesAny(of: ImageAdjustmentDescription(light: .init(exposure: -1.5))))
    }

    /// A step inserted ahead of the develop's steps would run after the develop it should precede.
    @Test func theDevelopTakesExactlyTheFirstRenderSteps() {
        #expect(Array(RenderStep.allCases.prefix(RAWDevelop.developSteps.count)) == RAWDevelop.developSteps)

        var everything = ImageAdjustmentDescription()
        for parameter in ImageAdjustmentDescription.Parameter.allCases {
            let range = parameter.range
            everything[parameter] = range.upperBound != 0 ? range.upperBound : range.lowerBound
        }

        let result = parameters(everything)
        let taken = Set(ImageAdjustmentDescription.Parameter.allCases.filter { result.remaining[$0] != everything[$0] })

        var read = Set<ImageAdjustmentDescription.Parameter>()
        for step in RAWDevelop.developSteps {
            guard case let .parameters(parameters) = step.reads else {
                Issue.record("\(step) reads a whole section")
                continue
            }
            read.formUnion(parameters)
        }

        #expect(taken == read)
        #expect(taken.allSatisfy { result.remaining[$0] == 0 })
    }

    // MARK: - White balance from a point

    @Test func thePickedWhiteMapsBackToTheSlidersThatDevelopIt() throws {
        let asShot = (temperature: 5000.0, tint: 10.0)

        for (temperature, tint) in [(0.5, 0.2), (-0.7, -0.6), (0.1, -1.0), (-1.0, 1.0), (0.0, 0.35)] {
            let forward = parameters(
                ImageAdjustmentDescription(color: .init(temperature: temperature, tint: tint)),
                asShotTemperature: asShot.temperature,
                asShotTint: asShot.tint
            )

            let back = RAWDevelop.whiteBalance(
                neutralTemperature: try #require(forward.neutralTemperature),
                neutralTint: try #require(forward.neutralTint),
                asShotTemperature: asShot.temperature,
                asShotTint: asShot.tint
            )

            #expect(abs(back.temperature - temperature) < 1e-9, "temperature \(temperature) came back \(back.temperature)")
            #expect(abs(back.tint - tint) < 1e-9, "tint \(tint) came back \(back.tint)")
        }
    }

    @Test func aPickBeyondTheSlidersStopsAtTheirEdges() {
        let warm = RAWDevelop.whiteBalance(neutralTemperature: 40000, neutralTint: 10_000, asShotTemperature: 5000, asShotTint: 10)
        #expect(warm.temperature == ImageAdjustmentDescription.Parameter.temperature.range.upperBound)
        #expect(warm.tint == ImageAdjustmentDescription.Parameter.tint.range.upperBound)

        let cool = RAWDevelop.whiteBalance(neutralTemperature: 2100, neutralTint: -10_000, asShotTemperature: 5000, asShotTint: 10)
        #expect(cool.temperature == ImageAdjustmentDescription.Parameter.temperature.range.lowerBound)
        #expect(cool.tint == ImageAdjustmentDescription.Parameter.tint.range.lowerBound)
    }
}
