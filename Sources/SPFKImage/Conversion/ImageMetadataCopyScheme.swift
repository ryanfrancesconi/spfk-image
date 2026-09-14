// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// Which of the source's metadata a converted image keeps. The raw values are stored in saved settings.
public enum ImageMetadataCopyScheme: String, Codable, CaseIterable, Sendable {
    /// Every field the output format holds, and the Finder tags.
    case copyAll

    /// Everything but GPS and its XMP copy. Location a camera stores inside its maker notes stays.
    case copyAllExceptLocation

    /// Only what displays the image: orientation, color and HDR headroom. Finder tags are not copied.
    case stripAll

    public var copiesFinderTags: Bool {
        self != .stripAll
    }
}
