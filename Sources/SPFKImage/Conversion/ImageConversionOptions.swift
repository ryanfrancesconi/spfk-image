// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import SPFKFileSystem
import UniformTypeIdentifiers

/// What ``ImageFormatConverter`` writes for each file.
public struct ImageConversionOptions: Codable, Hashable, Sendable {
    /// The output's type identifier. ``ImageFormatConverter/outputTypes`` lists those offered.
    public var format: String

    /// Encode quality from 0 to 1, for the types ``ImageFormatConverter/usesQuality(_:)`` accepts.
    public var quality: Double {
        didSet { quality = Self.sanitized(quality: quality) }
    }

    /// The longest edge in pixels, or `nil` for the source's own size. A smaller source is not enlarged.
    public var maxPixelSize: Int? {
        didSet { maxPixelSize = Self.sanitized(maxPixelSize: maxPixelSize) }
    }

    public var conflictScheme: FileConflictScheme

    public init(
        format: String = UTType.jpeg.identifier,
        quality: Double = ImageAdjustmentRenderer.defaultFileQuality,
        maxPixelSize: Int? = nil,
        conflictScheme: FileConflictScheme = .overwrite
    ) {
        self.format = format
        self.quality = Self.sanitized(quality: quality)
        self.maxPixelSize = Self.sanitized(maxPixelSize: maxPixelSize)
        self.conflictScheme = conflictScheme
    }

    private enum CodingKeys: String, CodingKey {
        case format
        case quality
        case maxPixelSize
        case conflictScheme
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ImageConversionOptions()

        try self.init(
            format: container.decodeIfPresent(String.self, forKey: .format) ?? defaults.format,
            quality: container.decodeIfPresent(Double.self, forKey: .quality) ?? defaults.quality,
            maxPixelSize: container.decodeIfPresent(Int.self, forKey: .maxPixelSize),
            conflictScheme: container.decodeIfPresent(FileConflictScheme.self, forKey: .conflictScheme) ?? defaults.conflictScheme
        )
    }

    private static func sanitized(quality: Double) -> Double {
        guard quality.isFinite else { return ImageAdjustmentRenderer.defaultFileQuality }
        return min(1, max(0, quality))
    }

    private static func sanitized(maxPixelSize: Int?) -> Int? {
        guard let maxPixelSize, maxPixelSize > 0 else { return nil }
        return maxPixelSize
    }
}
