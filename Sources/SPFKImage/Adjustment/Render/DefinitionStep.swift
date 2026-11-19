// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation

enum DefinitionStep {
    /// Scales the detail above the base by `1 + value × maximumGain`, darkening the base slightly (see
    /// ``LocalTone``).
    static func apply(_ image: CIImage, _ value: Double) -> CIImage {
        guard value != 0 else { return image }
        return LocalTone.apply(image, curve: ToneCurve.lifted(by: lift, value), detailGain: 1 + value * maximumGain)
    }

    // MARK: - Mapping from slider positions

    /// The detail gain added at full definition, and how far it moves the base.
    static let maximumGain: Double = 1
    static let lift: [Double] = [0, -0.02, -0.02, 0, 0]
}
