// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import SPFKTesting
import Testing

@testable import SPFKImage

/// A bypassed parameter keeps its value and renders as neutral.
@Suite(.tags(.file))
final class ImageAdjustmentBypassTests {
    typealias Parameter = ImageAdjustmentDescription.Parameter

    let context = CIContext()
    let input: CIImage

    init() throws {
        input = CIImage(cgImage: try CGImage.contentsOf(url: TestBundleResources.shared.songbird))
    }

    private func pixels(_ adjustments: ImageAdjustmentDescription) throws -> [Float] {
        try ImageAdjustmentChainPinTests.floatPixels(ImageAdjustmentRenderer.apply(adjustments, to: input), context: context)
    }

    @Test func aBypassedParameterRendersAsNeutralAndKeepsItsValue() throws {
        var bypassed = ImageAdjustmentChainPinTests.pinned
        bypassed.bypassed = [.exposure, .saturation]

        var neutralized = ImageAdjustmentChainPinTests.pinned
        neutralized.exposure = 0
        neutralized.saturation = 0

        #expect(try pixels(bypassed) == pixels(neutralized))
        #expect(bypassed.exposure == ImageAdjustmentChainPinTests.pinned.exposure)
        #expect(bypassed.saturation == ImageAdjustmentChainPinTests.pinned.saturation)
    }

    @Test func everythingBypassedIsAnIdentityRenderButNotEmpty() throws {
        var adjustments = ImageAdjustmentChainPinTests.pinned
        adjustments.bypassed = Set(Parameter.allCases)

        #expect(!adjustments.isEmpty)
        #expect(adjustments.effective.isEmpty)
        #expect(try pixels(adjustments) == pixels(ImageAdjustmentDescription()))
    }

    @Test func aSectionSwitchedOffAtItsDefaultsIsStillSomethingToStore() {
        #expect(!ImageAdjustmentDescription(bypassed: [.vignette]).isEmpty)
        #expect(ImageAdjustmentDescription(bypassed: [.vignette]).effective.isEmpty)
    }

    @Test func theBypassedPartKeepsOnlyTheBypassedValues() {
        let adjustments = ImageAdjustmentDescription(exposure: 1, saturation: 0.5, bypassed: [.saturation, .vignette])
        #expect(adjustments.bypassedPart == ImageAdjustmentDescription(saturation: 0.5, bypassed: [.saturation, .vignette]))
    }

    @Test func codableRoundTripKeepsTheBypassedSet() throws {
        let adjustments = ImageAdjustmentDescription(exposure: 1, vignette: 0.5, bypassed: [.vignette])
        let decoded = try JSONDecoder().decode(ImageAdjustmentDescription.self, from: JSONEncoder().encode(adjustments))
        #expect(decoded == adjustments)
    }

    @Test func dataWithoutTheKeyDecodesWithNothingBypassed() throws {
        let decoded = try JSONDecoder().decode(ImageAdjustmentDescription.self, from: Data(#"{"exposure":1}"#.utf8))
        #expect(decoded.bypassed.isEmpty)
        #expect(decoded.exposure == 1)
    }

    @Test func anUnknownBypassedParameterIsDropped() throws {
        let json = #"{"exposure":1,"bypassed":["exposure","noSuchParameter"]}"#
        let decoded = try JSONDecoder().decode(ImageAdjustmentDescription.self, from: Data(json.utf8))
        #expect(decoded.bypassed == [.exposure])
    }
}
