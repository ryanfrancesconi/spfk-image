// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// Unpremultiplied RGBA samples, four per pixel and little-endian when 16-bit, rows from the top.
public struct RGBAPixelBuffer: Sendable {
    public let data: Data
    public let width: Int
    public let height: Int

    /// 8 or 16.
    public let bitsPerComponent: Int

    /// `false` when the image has no alpha channel, so every alpha sample is opaque.
    public let hasAlpha: Bool

    /// The profile of the color space the samples are in.
    public let iccProfile: Data
}
