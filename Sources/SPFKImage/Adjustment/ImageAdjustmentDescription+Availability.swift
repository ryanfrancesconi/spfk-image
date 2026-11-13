// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    /// The sections and parameters a kind of media can render. Curves has no parameters, so it is
    /// available only as a whole group.
    public struct Availability: Hashable, Sendable {
        public var groups: Set<Group>
        /// Parameters held at neutral inside an available group.
        public var excludedParameters: Set<Parameter>

        public init(groups: Set<Group>, excludedParameters: Set<Parameter> = []) {
            self.groups = groups
            self.excludedParameters = excludedParameters
        }

        /// What a video renders, through a per-frame Core Image composition.
        public static let video = Availability(
            groups: [.light, .color, .curves, .levels, .selectiveColor, .colorGrading, .blackAndWhite, .vignette, .detail],
            excludedParameters: [.brilliance, .definition, .noiseReduction]
        )

        /// No adjustment at all: what a file that only takes orientation shows.
        public static let empty = Availability(groups: [])

        public func contains(_ parameter: Parameter) -> Bool {
            groups.contains(parameter.group) && !excludedParameters.contains(parameter)
        }
    }

    /// Every group outside `availability` and every excluded parameter at neutral, and only available
    /// groups left in ``bypassed``.
    public func restricted(to availability: Availability) -> ImageAdjustmentDescription {
        var result = self

        for group in Group.allCases where !availability.groups.contains(group) {
            result.reset(group)
        }

        for parameter in availability.excludedParameters {
            result[parameter] = 0
        }

        result.bypassed.formIntersection(availability.groups)
        return result
    }
}
