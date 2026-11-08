// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// An image's tonal distribution in ``binCount`` bins over sRGB-encoded values, black first. Each
/// channel's bins hold shares of the image's pixels and sum to 1.
public struct ImageHistogram: Hashable, Sendable {
    public static let binCount = 256

    public var red: [Float]
    public var green: [Float]
    public var blue: [Float]
    /// Rec. 709 luma of the encoded values.
    public var luminance: [Float]

    public init(red: [Float], green: [Float], blue: [Float], luminance: [Float]) {
        self.red = red
        self.green = green
        self.blue = blue
        self.luminance = luminance
    }
}
