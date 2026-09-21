// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import ImageIO
import Testing

@testable import SPFKImage

/// What Strip All asks ImageIO to remove, and the two Apple maker note keys it keeps so an iPhone photo's gain map
/// still displays as HDR.
@Suite
struct ImageFormatConverterStripTests {
    private let properties: [String: Any] = [
        kCGImagePropertyExifDictionary as String: [kCGImagePropertyExifDateTimeOriginal as String: "2026:09:21 10:00:00"],
        kCGImagePropertyMakerAppleDictionary as String: ["33": 1.0, "48": 0.5, "8": 3],
    ]

    @Test func strippingRemovesEveryAppleKeyButTheHeadroomKeys() throws {
        let options = ImageFormatConverter.strippingProperties(properties)
        let apple = try #require(options[kCGImagePropertyMakerAppleDictionary] as? [String: Any])

        #expect(Set(apple.keys) == ["8"])
    }

    /// Naming a dictionary the source lacks writes an empty one in its place.
    @Test func strippingNamesOnlyWhatTheSourceHolds() {
        let options = ImageFormatConverter.strippingProperties(properties)

        #expect(options[kCGImagePropertyExifDictionary] != nil)
        #expect(options[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func aRenderKeepsOnlyTheHeadroomKeys() throws {
        let kept = ImageFormatConverter.headroomProperties(properties)
        let apple = try #require(kept[kCGImagePropertyMakerAppleDictionary] as? [String: Any])

        #expect(Set(apple.keys) == ImageFormatConverter.appleHeadroomKeys)
        #expect(ImageFormatConverter.headroomProperties([:]).isEmpty)
    }
}
