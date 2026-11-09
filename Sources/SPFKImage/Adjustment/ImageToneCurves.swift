// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// Tone curves over sRGB-encoded values: one for all three channels together, then one per channel.
///
/// Each channel's points run in increasing x, at least ``minimumGap`` apart, at most
/// ``maximumPointCount``, inside 0…1. The first and last are the curve's ends, and it is flat beyond
/// them. Sanitized on construction and assignment, so stored data breaking this is repaired.
public struct ImageToneCurves: Hashable, Sendable, Codable {
    public struct Point: Hashable, Sendable, Codable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public enum Channel: String, CaseIterable, Sendable {
        case rgb
        case red
        case green
        case blue
    }

    /// Applied first, to all three channels.
    public var rgb: [Point] { didSet { rgb = Self.sanitize(rgb) } }
    public var red: [Point] { didSet { red = Self.sanitize(red) } }
    public var green: [Point] { didSet { green = Self.sanitize(green) } }
    public var blue: [Point] { didSet { blue = Self.sanitize(blue) } }

    public static let identityPoints = [Point(x: 0, y: 0), Point(x: 1, y: 1)]
    public static let identity = ImageToneCurves()
    public static let minimumGap: Double = 0.01
    public static let maximumPointCount = 16
    /// Lets a point placed exactly ``minimumGap`` from its neighbor survive the rounding of `x + gap`.
    static let gapTolerance: Double = 1e-9

    public init(
        rgb: [Point] = identityPoints,
        red: [Point] = identityPoints,
        green: [Point] = identityPoints,
        blue: [Point] = identityPoints
    ) {
        self.rgb = Self.sanitize(rgb)
        self.red = Self.sanitize(red)
        self.green = Self.sanitize(green)
        self.blue = Self.sanitize(blue)
    }

    enum CodingKeys: String, CodingKey {
        case rgb, red, green, blue
    }

    /// A missing channel decodes as identity.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            rgb: try c.decodeIfPresent([Point].self, forKey: .rgb) ?? Self.identityPoints,
            red: try c.decodeIfPresent([Point].self, forKey: .red) ?? Self.identityPoints,
            green: try c.decodeIfPresent([Point].self, forKey: .green) ?? Self.identityPoints,
            blue: try c.decodeIfPresent([Point].self, forKey: .blue) ?? Self.identityPoints
        )
    }

    public var isIdentity: Bool {
        Channel.allCases.allSatisfy { self[$0] == Self.identityPoints }
    }

    public subscript(channel: Channel) -> [Point] {
        get {
            switch channel {
            case .rgb: rgb
            case .red: red
            case .green: green
            case .blue: blue
            }
        }
        set {
            switch channel {
            case .rgb: rgb = newValue
            case .red: red = newValue
            case .green: green = newValue
            case .blue: blue = newValue
            }
        }
    }

    /// Clamped to 0…1, sorted, with a point too close to the one before it dropped; the last point is
    /// kept over its neighbor. Identity when fewer than two points remain.
    static func sanitize(_ points: [Point]) -> [Point] {
        let sorted = points
            .filter { $0.x.isFinite && $0.y.isFinite }
            .map { Point(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }
            .sorted { $0.x < $1.x }

        var result: [Point] = []

        for (index, point) in sorted.enumerated() {
            if let last = result.last, point.x - last.x < minimumGap - gapTolerance {
                guard index == sorted.count - 1, result.count > 1 else { continue }
                result.removeLast()
            }
            result.append(point)
        }

        if result.count > maximumPointCount, let last = result.last {
            result = Array(result.prefix(maximumPointCount - 1)) + [last]
        }

        return result.count >= 2 ? result : identityPoints
    }
}

extension ImageToneCurves {
    /// `channel`'s curve as a function of its input, as the renderer draws it.
    public func interpolation(_ channel: Channel) -> MonotoneCubicInterpolation {
        let points = self[channel]
        return MonotoneCubicInterpolation(x: points.map(\.x), y: points.map(\.y))
    }
}
