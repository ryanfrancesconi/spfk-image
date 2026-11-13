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

    @Test func videoLeavesOutGrainAndTheLocalDetailSteps() {
        let full = Self.full
        let restricted = full.restricted(to: .video)
        let left: Set<ImageAdjustmentDescription.Parameter> = [.brilliance, .definition, .noiseReduction]

        for parameter in ImageAdjustmentDescription.Parameter.allCases {
            let kept = parameter.group != .grain && !left.contains(parameter)
            #expect(restricted[parameter] == (kept ? full[parameter] : 0), "\(parameter)")
        }

        #expect(restricted.curves == full.curves)
        #expect(restricted.bypassed == Set(ImageAdjustmentDescription.Group.allCases).subtracting([.grain]))
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
