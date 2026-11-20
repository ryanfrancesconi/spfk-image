// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// How a photo was captured, as its file records it.
///
/// The raw values are stored; never renumber them.
public struct CaptureModes: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let raw = CaptureModes(rawValue: 1 << 0)
    public static let hdr = CaptureModes(rawValue: 1 << 1)
    public static let portrait = CaptureModes(rawValue: 1 << 2)
    public static let livePhoto = CaptureModes(rawValue: 1 << 3)
}
