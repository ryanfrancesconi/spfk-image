// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

extension ImageAdjustmentDescription {
    /// How far each of the levels curve's five points sits from its identity input position (see
    /// ``positions``).
    public struct Levels: Hashable, Sendable, Codable {
        public var black: Double
        public var shadow: Double
        public var mid: Double
        public var highlight: Double
        public var white: Double

        public init(black: Double = 0, shadow: Double = 0, mid: Double = 0, highlight: Double = 0, white: Double = 0) {
            self.black = black
            self.shadow = shadow
            self.mid = mid
            self.highlight = highlight
            self.white = white
        }

        public var isNeutral: Bool { self == Self() }

        /// The input positions of the curve's five points, which map to outputs 0, ¼, ½, ¾ and 1, in
        /// sRGB-encoded values.
        ///
        /// Read in increasing order whatever is stored: black and white first, then the midpoint between
        /// them, then each quarter point between its neighbors, each at least ``minimumGap`` from the
        /// next. Assigning stores each position's offset from identity.
        public var positions: [Double] {
            get {
                let x = zip(offsets, Self.identity).map { $0 + $1 }
                let gap = Self.minimumGap

                func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double { min(max(value, low), high) }

                let black = clamp(x[0], 0, 1 - 4 * gap)
                let white = clamp(x[4], black + 4 * gap, 1)
                let mid = clamp(x[2], black + 2 * gap, white - 2 * gap)
                let shadow = clamp(x[1], black + gap, mid - gap)
                let highlight = clamp(x[3], mid + gap, white - gap)

                return [black, shadow, mid, highlight, white]
            }
            set {
                let offsets = zip(newValue, Self.identity).map { $0 - $1 }
                guard offsets.count == 5 else { return }

                black = offsets[0]
                shadow = offsets[1]
                mid = offsets[2]
                highlight = offsets[3]
                white = offsets[4]
            }
        }

        private var offsets: [Double] {
            [black, shadow, mid, highlight, white]
        }

        /// The points' input positions at identity, which are also their fixed outputs.
        public static let identity: [Double] = [0, 0.25, 0.5, 0.75, 1]

        /// The closest two neighboring points can sit.
        public static let minimumGap: Double = 0.01
    }
}
