// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// A RAW still's thumbnail drawn through a develop rather than decoded as stored.
///
/// `fingerprint` names the develop among the file's others, since a cache keyed by file alone would
/// serve a previous develop's image. The supplier derives it from whatever defines its develop.
public struct StillThumbnailRecipe: Sendable, Hashable {
    public let adjustments: ImageAdjustmentDescription

    /// Nil develops with the system's default.
    public let decoderVersion: String?

    public let fingerprint: String

    public init(adjustments: ImageAdjustmentDescription, decoderVersion: String?, fingerprint: String) {
        self.adjustments = adjustments
        self.decoderVersion = decoderVersion
        self.fingerprint = fingerprint
    }
}
