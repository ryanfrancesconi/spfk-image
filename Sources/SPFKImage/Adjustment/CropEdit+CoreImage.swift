// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import SPFKBase

extension CropEdit {
    /// The kept region of `image`, an upright decode at any scale, axis-aligned and of
    /// ``keptPixelSize(imageWidth:imageHeight:)``, its extent moved to the origin. The crop is first
    /// ``contained(imageWidth:imageHeight:)``, so nothing outside the picture is sampled.
    public func apply(to image: CIImage) -> CIImage {
        guard !isIdentity else { return image }

        let extent = image.extent.integral
        let imageWidth = Int(extent.width)
        let imageHeight = Int(extent.height)
        guard imageWidth > 0, imageHeight > 0 else { return image }

        let crop = contained(imageWidth: imageWidth, imageHeight: imageHeight)
        let size = keptPixelSize(imageWidth: imageWidth, imageHeight: imageHeight)
        let topLeftCenter = crop.pixelCenter(imageWidth: imageWidth, imageHeight: imageHeight)
        let center = CGPoint(x: extent.minX + topLeftCenter.x, y: extent.maxY - topLeftCenter.y)

        // Clamped, so a rounded edge on the picture's border repeats it rather than turning transparent.
        var turned = image.clampedToExtent()

        if crop.straighten != 0 {
            // Clockwise as displayed is negative in Core Image's y-up space.
            let radians = -crop.straighten * .pi / 180
            let transform = CGAffineTransform(translationX: -center.x, y: -center.y)
                .concatenating(CGAffineTransform(rotationAngle: radians))
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
            turned = turned.transformed(by: transform)
        }

        let origin = CGPoint(
            x: (center.x - Double(size.width) / 2).rounded(),
            y: (center.y - Double(size.height) / 2).rounded()
        )
        let kept = turned.cropped(to: CGRect(origin: origin, size: CGSize(width: size.width, height: size.height)))

        return kept.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
    }
}
