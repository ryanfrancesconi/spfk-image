// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    /// The input positions of the levels curve's five points, which map to outputs 0, ¼, ½, ¾ and 1,
    /// in sRGB-encoded values.
    ///
    /// Read in increasing order whatever is stored: black and white first, then the midpoint between
    /// them, then each quarter point between its neighbors, each at least ``levelsMinimumGap`` from the
    /// next. Assigning stores each position's offset from identity.
    public var levelsPositions: [Double] {
        get {
            let x = zip(Parameter.levels, Self.levelsIdentity).map { self[$0] + $1 }
            let gap = Self.levelsMinimumGap

            func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double { min(max(value, low), high) }

            let black = clamp(x[0], 0, 1 - 4 * gap)
            let white = clamp(x[4], black + 4 * gap, 1)
            let mid = clamp(x[2], black + 2 * gap, white - 2 * gap)
            let shadow = clamp(x[1], black + gap, mid - gap)
            let highlight = clamp(x[3], mid + gap, white - gap)

            return [black, shadow, mid, highlight, white]
        }
        set {
            for (parameter, (position, identity)) in zip(Parameter.levels, zip(newValue, Self.levelsIdentity)) {
                self[parameter] = position - identity
            }
        }
    }

    /// Whether any levels point is away from identity.
    public var hasLevels: Bool {
        Parameter.levels.contains { self[$0] != 0 }
    }

    /// The levels points' input positions at identity, which are also their fixed outputs.
    public static let levelsIdentity: [Double] = [0, 0.25, 0.5, 0.75, 1]

    /// The closest two neighboring levels points can sit.
    public static let levelsMinimumGap: Double = 0.01
}

extension ImageAdjustmentDescription.Parameter {
    /// The levels curve's points, black to white.
    public static let levels: [Self] = [.levelsBlack, .levelsShadow, .levelsMid, .levelsHighlight, .levelsWhite]
}
