// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// Why ``ImageAdjustmentRenderer/renderFile(_:source:destination:quality:)`` wrote nothing.
public enum ImageAdjustmentRenderError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The destination already exists. Nothing was written or removed.
    case destinationExists
    /// The source could not be opened as an image, or reports no pixel dimensions.
    case unreadable
    /// The source holds more than one image, and rendering the first would drop the rest.
    case multipleImages
    /// The source is neither RGB nor grayscale, for example CMYK or indexed color.
    case unsupportedColorModel
    case renderFailed
    /// ImageIO has no encoder for this type identifier.
    case unwritableType(String)
    case encodeFailed
    /// The written file's orientation or pixel dimensions differ from the source's.
    case readBackMismatch

    public var description: String {
        switch self {
        case .destinationExists: "The destination already exists"
        case .unreadable: "The source could not be read as an image"
        case .multipleImages: "The source holds more than one image"
        case .unsupportedColorModel: "The source's color model cannot be rendered"
        case .renderFailed: "Core Image could not render the adjusted image"
        case let .unwritableType(type): "ImageIO cannot write \(type)"
        case .encodeFailed: "The adjusted image could not be encoded"
        case .readBackMismatch: "The written file does not match the source's orientation or dimensions"
        }
    }
}
