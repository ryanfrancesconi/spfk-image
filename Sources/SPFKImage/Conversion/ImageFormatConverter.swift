// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import SPFKBase
import SPFKFileSystem
import UniformTypeIdentifiers

/// Converts one image file into another format through ImageIO.
///
/// Copies through ImageIO where that keeps the source's pixels and metadata, and renders upright through
/// Core Image where it would not. The output is written elsewhere and moved into place only once it reads
/// back at the size it was written at, so it never exists half-written.
public struct ImageFormatConverter: Sendable {
    public let source: ImageConversionSource

    public init(source: ImageConversionSource) {
        self.source = source
    }

    /// Converts the source's primary image and returns the source as written, its output renamed by a
    /// `.unique` conflict. Neither `input` nor `originalInput` is ever written.
    public func convert() throws -> ImageConversionSource {
        try Task.checkCancellation()

        // Ahead of the conflict handling, which replaces an existing output.
        for protected in [source.input, source.originalInput].compactMap({ $0 })
            where FileSystem.isSameFile(source.output, protected)
        {
            throw ImageConversionError.outputReplacesInput(protected)
        }

        guard let type = UTType(source.options.format),
              Self.writableTypeIdentifiers.contains(type.identifier)
        else { throw ImageConversionError.unwritableType(source.options.format) }

        var converted = source

        if converted.output.exists {
            switch converted.options.conflictScheme {
            case .overwrite:
                break

            case .error:
                throw ImageConversionError.outputExists(converted.output)

            case .unique:
                converted.output = FileSystem.nextAvailableURL(converted.output)
            }
        }

        let workDirectory = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: converted.output,
            create: true
        )

        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let written = workDirectory.appending(component: converted.output.lastPathComponent, directoryHint: .notDirectory)

        try autoreleasepool {
            try write(to: written, type: type)
        }

        #if os(macOS)
            if converted.options.metadata.copiesFinderTags {
                try (source.originalInput ?? source.input).copyFinderTags(to: written)
            }
        #endif

        try Task.checkCancellation()

        if converted.output.exists {
            // New metadata only, or the replaced file's own Finder tags survive into its replacement.
            _ = try FileManager.default.replaceItemAt(converted.output, withItemAt: written, options: .usingNewMetadataOnly)
        } else {
            try FileManager.default.moveItem(at: written, to: converted.output)
        }

        return converted
    }
}
