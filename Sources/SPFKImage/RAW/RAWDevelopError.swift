// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// Why ``RAWDevelop`` returned no image.
public enum RAWDevelopError: LocalizedError, Equatable, Sendable {
    /// The file is not a RAW image, or Core Image could not open it as one.
    case unreadable
    /// The file cannot be developed with this decoder version on this system.
    case unsupportedDecoderVersion(String)
    case developFailed

    public var errorDescription: String? {
        switch self {
        case .unreadable:
            "The file could not be read as a RAW image."
        case let .unsupportedDecoderVersion(version):
            "This Mac cannot develop the file with RAW decoder version \(version)."
        case .developFailed:
            "The RAW image could not be developed."
        }
    }
}
