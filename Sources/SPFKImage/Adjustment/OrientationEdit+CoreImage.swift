// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import ImageIO
import SPFKBase

extension OrientationEdit {
    /// `image` with this edit performed, its extent moved back to the origin.
    public func apply(to image: CIImage) -> CIImage {
        guard !isIdentity else { return image }

        let oriented = image.oriented(cgImagePropertyOrientation)

        return oriented.transformed(by: CGAffineTransform(translationX: -oriented.extent.minX, y: -oriented.extent.minY))
    }

    public var cgImagePropertyOrientation: CGImagePropertyOrientation {
        CGImagePropertyOrientation(rawValue: UInt32(rawValue)) ?? .up
    }
}
