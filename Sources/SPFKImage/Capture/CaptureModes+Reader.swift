// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation
import ImageIO

extension CaptureModes {
    /// The modes `source` records, given the properties of its image at index 0.
    ///
    /// Reads metadata only and never decodes an auxiliary map. A RAW source skips the file-level
    /// properties, whose only gain map belongs to the embedded preview.
    public init(source: CGImageSource, primaryProperties: [CFString: Any]) {
        var modes: CaptureModes = []

        if Self.isLivePhoto(primaryProperties) {
            modes.insert(.livePhoto)
        }

        guard !RAWDevelop.isRAW(source) else {
            modes.insert(.raw)
            self = modes
            return
        }

        let types = Self.auxiliaryDataTypes(of: source)

        if !types.isDisjoint(with: Self.gainMapTypes) {
            modes.insert(.hdr)
        }

        // Photos marks any photo carrying depth as Portrait, matte or not.
        if types.contains(kCGImageAuxiliaryDataTypeDisparity as String)
            || types.contains(kCGImageAuxiliaryDataTypeDepth as String) {
            modes.insert(.portrait)
        }

        self = modes
    }

    /// Apple's maker-note tag 17 holds the Live Photo's content identifier, shared with its movie.
    static func isLivePhoto(_ properties: [CFString: Any]) -> Bool {
        let makerApple = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any]
        guard let identifier = makerApple?["17"] as? String else { return false }
        return !identifier.isEmpty
    }

    private static var gainMapTypes: Set<String> {
        var types: Set<String> = [kCGImageAuxiliaryDataTypeHDRGainMap as String]

        if #available(macOS 15, iOS 18, *) {
            types.insert(kCGImageAuxiliaryDataTypeISOGainMap as String)
        }

        return types
    }

    /// The auxiliary data types listed for the primary image, leaving out any carried by its thumbnail.
    private static func auxiliaryDataTypes(of source: CGImageSource) -> Set<String> {
        guard let file = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
              let contents = file[kCGImagePropertyFileContentsDictionary] as? [CFString: Any],
              let images = contents[kCGImagePropertyImages] as? [[CFString: Any]]
        else { return [] }

        let primary = CGImageSourceGetPrimaryImageIndex(source)
        guard primary < images.count else { return [] }

        let entries = images[primary][kCGImagePropertyAuxiliaryData] as? [[CFString: Any]] ?? []

        return Set(entries.compactMap { entry -> String? in
            guard (entry["embeddedInThumbnail" as CFString] as? Int) != 1 else { return nil }
            return entry[kCGImagePropertyAuxiliaryDataType] as? String
        })
    }
}
