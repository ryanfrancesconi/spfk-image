// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import UniformTypeIdentifiers

/// The output types a conversion offers: every image type ImageIO writes except GPU textures and icons, and the
/// types of the encoders supplied.
public struct ImageConversionFormats: Sendable {
    /// Encoders for a type ImageIO writes itself, or cannot read back, are left out, as is a second encoder for a type.
    public let encoders: [any ImageFileEncoder]

    public init(encoders: [any ImageFileEncoder] = []) {
        var identifiers = Set<String>()

        self.encoders = encoders.filter {
            let identifier = $0.type.identifier

            return !ImageFormatConverter.writableTypeIdentifiers.contains(identifier)
                && ImageFormatConverter.readableTypeIdentifiers.contains(identifier)
                && identifiers.insert(identifier).inserted
        }
    }

    /// Types that keep metadata first, each group ordered by name.
    public var outputTypes: [UTType] {
        (ImageFormatConverter.imageIOOutputTypes + encoders.map(\.type)).sorted { lhs, rhs in
            guard carriesMetadata(lhs) == carriesMetadata(rhs) else { return carriesMetadata(lhs) }
            return Self.name(of: lhs).localizedStandardCompare(Self.name(of: rhs)) == .orderedAscending
        }
    }

    public func canWrite(_ type: UTType) -> Bool {
        ImageFormatConverter.writableTypeIdentifiers.contains(type.identifier) || encoder(for: type) != nil
    }

    /// Whether ``ImageConversionOptions/quality`` changes a file written as `type`.
    public func usesQuality(_ type: UTType) -> Bool {
        encoder(for: type)?.usesQuality ?? ImageFormatConverter.usesQuality(type)
    }

    /// Whether a converted file of `type` keeps the source's EXIF, GPS and XMP. `false` for a type not known to.
    public func carriesMetadata(_ type: UTType) -> Bool {
        encoder(for: type) != nil || ImageFormatConverter.carriesMetadata(type)
    }

    func encoder(for type: UTType) -> (any ImageFileEncoder)? {
        encoders.first { $0.type.identifier == type.identifier }
    }

    private static func name(of type: UTType) -> String {
        type.localizedDescription ?? type.identifier
    }
}
