// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import UniformTypeIdentifiers

/// Why ``ImageFormatConverter`` left no output.
public enum ImageConversionError: LocalizedError, Equatable, Sendable {
    /// The output is the input, or the file a render of it stands in for.
    case outputReplacesInput(URL)
    /// The output exists and the conflict scheme is `.error`.
    case outputExists(URL)
    /// The input could not be opened as an image, or reports no pixel dimensions.
    case unreadable(URL)
    /// Neither ImageIO nor a supplied encoder writes this type identifier.
    case unwritableType(String)
    /// The image is larger on a side than the type identifier holds.
    case exceedsMaxPixelSize(String, Int)
    case renderFailed
    case encodeFailed(String)
    /// The written file does not display at the size it was written at.
    case readBackMismatch

    public var errorDescription: String? {
        switch self {
        case let .outputReplacesInput(url):
            "Converting \(url.lastPathComponent) would replace it. Choose a different folder or format."
        case let .outputExists(url):
            "\(url.lastPathComponent) already exists."
        case .unreadable:
            "The file could not be read as an image."
        case let .unwritableType(type):
            "This Mac cannot write \(Self.name(of: type))."
        case let .exceedsMaxPixelSize(type, maxPixelSize):
            "\(Self.name(of: type)) holds images up to \(maxPixelSize) pixels on a side. Set a maximum size to convert this one."
        case .renderFailed:
            "The image could not be rendered."
        case let .encodeFailed(type):
            "The image could not be encoded as \(Self.name(of: type))."
        case .readBackMismatch:
            "The converted file does not match the size it was written at."
        }
    }

    private static func name(of type: String) -> String {
        UTType(type)?.localizedDescription ?? type
    }
}
