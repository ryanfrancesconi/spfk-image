// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import UniformTypeIdentifiers

/// Writes an image type ImageIO has no encoder for, handed to ``ImageFormatConverter`` through
/// ``ImageConversionFormats``.
public protocol ImageFileEncoder: Sendable {
    var type: UTType { get }

    /// Whether ``ImageFileEncoderInput/quality`` changes what is written.
    var usesQuality: Bool { get }

    /// The longest edge the format holds, or `nil` for no limit. A larger image is refused before it renders.
    var maxPixelSize: Int? { get }

    func encode(_ input: ImageFileEncoderInput) throws -> Data
}
