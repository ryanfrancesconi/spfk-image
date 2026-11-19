// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreGraphics
import Foundation

/// What a ``RenderStep`` needs beyond the description.
struct RenderFrame: Sendable {
    /// The extent of the image the render began with.
    let extent: CGRect
    /// The image's size relative to the full-resolution source.
    let sourceScale: Double
    let grainSeed: Int64
}
