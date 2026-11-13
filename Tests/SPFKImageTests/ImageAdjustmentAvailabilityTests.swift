// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import Testing

@testable import SPFKImage

@Suite
struct ImageAdjustmentAvailabilityTests {
    /// Every parameter off neutral, the curves bent and every group bypassed.
    static var full: ImageAdjustmentDescription {
        var description = ImageAdjustmentDescription(
            curves: ImageToneCurves(rgb: [.init(x: 0, y: 0), .init(x: 0.5, y: 0.7), .init(x: 1, y: 1)])
        )
        for parameter in ImageAdjustmentDescription.Parameter.allCases {
            let range = parameter.range
            description[parameter] = range.upperBound != 0 ? range.upperBound / 2 : range.lowerBound / 2
        }
        description.bypassed = Set(ImageAdjustmentDescription.Group.allCases)
        return description
    }

    @Test func videoKeepsEverything() {
        #expect(Self.full.restricted(to: .video) == Self.full)
    }

    @Test func anExcludedParameterGoesToNeutral() {
        let restricted = Self.full.restricted(to: .init(groups: [.light, .detail], excludedParameters: [.brilliance, .definition]))

        #expect(restricted.light.brilliance == 0)
        #expect(restricted.detail.definition == 0)
        #expect(restricted.light.exposure == Self.full.light.exposure)
        #expect(restricted.detail.noiseReduction == Self.full.detail.noiseReduction)
        #expect(restricted.bypassed == [.light, .detail])
    }

    @Test func aGroupLeftOutLosesItsCurvePoints() {
        let restricted = Self.full.restricted(to: .init(groups: [.light]))
        #expect(restricted.curves.isIdentity)
        #expect(restricted.bypassed == [.light])
    }

    @Test func emptyLeavesNothing() {
        #expect(Self.full.restricted(to: .empty).isEmpty)
    }

    @Test func restrictingTwiceChangesNothingMore() {
        let once = Self.full.restricted(to: .video)
        #expect(once.restricted(to: .video) == once)
    }
}
