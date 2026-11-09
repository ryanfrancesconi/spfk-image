// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// A smooth curve through points in increasing x that never overshoots them (Fritsch–Carlson), flat
/// beyond the first and last.
///
/// Between two points the curve stays inside their y range, so points inside 0…1 give a curve inside
/// 0…1, and points that never decrease give a curve that never decreases.
public struct MonotoneCubicInterpolation: Sendable {
    public let x: [Double]
    public let y: [Double]
    private let tangents: [Double]

    /// `x` must be strictly increasing and as long as `y`; with fewer than two points the curve is the
    /// identity.
    public init(x: [Double], y: [Double]) {
        let count = min(x.count, y.count)
        self.x = Array(x.prefix(count))
        self.y = Array(y.prefix(count))
        tangents = Self.tangents(x: self.x, y: self.y)
    }

    public func value(at input: Double) -> Double {
        guard x.count >= 2, let first = x.first, let last = x.last else { return input }

        if input <= first { return y[0] }
        if input >= last { return y[y.count - 1] }

        var upper = 1
        while x[upper] < input {
            upper += 1
        }

        return hermite(segment: upper - 1, at: input)
    }

    /// The curve at `count` evenly spaced inputs from 0 to 1.
    public func sample(count: Int) -> [Double] {
        guard count > 1 else { return count == 1 ? [value(at: 0)] : [] }

        guard x.count >= 2 else {
            return (0 ..< count).map { Double($0) / Double(count - 1) }
        }

        var result = [Double]()
        result.reserveCapacity(count)
        var segment = 0

        for index in 0 ..< count {
            let input = Double(index) / Double(count - 1)

            if input <= x[0] {
                result.append(y[0])
            } else if input >= x[x.count - 1] {
                result.append(y[y.count - 1])
            } else {
                while x[segment + 1] < input {
                    segment += 1
                }
                result.append(hermite(segment: segment, at: input))
            }
        }

        return result
    }

    private func hermite(segment k: Int, at input: Double) -> Double {
        let width = x[k + 1] - x[k]
        let t = (input - x[k]) / width
        let t2 = t * t
        let t3 = t2 * t

        return (2 * t3 - 3 * t2 + 1) * y[k]
            + (t3 - 2 * t2 + t) * width * tangents[k]
            + (-2 * t3 + 3 * t2) * y[k + 1]
            + (t3 - t2) * width * tangents[k + 1]
    }

    private static func tangents(x: [Double], y: [Double]) -> [Double] {
        let count = x.count
        guard count >= 2 else { return [Double](repeating: 0, count: count) }

        let slopes = (0 ..< count - 1).map { (y[$0 + 1] - y[$0]) / (x[$0 + 1] - x[$0]) }
        var m = [Double](repeating: 0, count: count)
        m[0] = slopes[0]
        m[count - 1] = slopes[count - 2]

        for k in 1 ..< max(1, count - 1) {
            m[k] = slopes[k - 1] * slopes[k] > 0 ? (slopes[k - 1] + slopes[k]) / 2 : 0
        }

        for k in 0 ..< count - 1 {
            guard slopes[k] != 0 else {
                m[k] = 0
                m[k + 1] = 0
                continue
            }

            let a = m[k] / slopes[k]
            let b = m[k + 1] / slopes[k]
            let length = a * a + b * b

            if length > 9 {
                let scale = 3 / length.squareRoot()
                m[k] = scale * a * slopes[k]
                m[k + 1] = scale * b * slopes[k]
            }
        }

        return m
    }
}
