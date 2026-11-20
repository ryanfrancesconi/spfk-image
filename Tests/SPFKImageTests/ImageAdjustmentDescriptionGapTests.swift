// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKBase
import Testing

@testable import SPFKImage

/// A stored adjustment written before a section or field existed still decodes.
struct ImageAdjustmentDescriptionGapTests {
    @Test func aMissingSectionAndFieldDecodeNeutral() throws {
        var original = ImageAdjustmentDescription(
            light: .init(exposure: 1.25),
            color: .init(saturation: 0.3, temperature: -0.4),
            detail: .init(sharpness: 0.6, noiseReduction: 0.2),
            grain: .init(amount: 0.5)
        )
        original.bypassed = [.light]

        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["grain"] = nil
        var detail = try #require(json["detail"] as? [String: Any])
        detail["noiseReduction"] = nil
        json["detail"] = detail
        let data = try JSONSerialization.data(withJSONObject: json)

        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ImageAdjustmentDescription.self, from: data) }

        let decoded = try ImageAdjustmentDescription.decodeFillingGaps(from: data)

        var expected = original
        expected.grain = .init()
        expected.detail.noiseReduction = 0
        #expect(decoded == expected)
    }
}
