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
        neutralized.light.exposure = 0
        neutralized.color.saturation = 0

        #expect(try pixels(bypassed) == pixels(neutralized))
        #expect(bypassed.light.exposure == ImageAdjustmentChainPinTests.pinned.light.exposure)
        #expect(bypassed.color.saturation == ImageAdjustmentChainPinTests.pinned.color.saturation)
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
        let adjustments = ImageAdjustmentDescription(
            light: .init(exposure: 1),
            color: .init(saturation: 0.5),
            bypassed: [.saturation, .vignette]
        )
        #expect(adjustments.unrenderedPart == ImageAdjustmentDescription(color: .init(saturation: 0.5), bypassed: [.saturation, .vignette]))
    }

    @Test func codableRoundTripKeepsTheBypassedSet() throws {
        let adjustments = ImageAdjustmentDescription(light: .init(exposure: 1), vignette: .init(amount: 0.5), bypassed: [.vignette])
        let decoded = try JSONDecoder().decode(ImageAdjustmentDescription.self, from: JSONEncoder().encode(adjustments))
        #expect(decoded == adjustments)
    }
}
