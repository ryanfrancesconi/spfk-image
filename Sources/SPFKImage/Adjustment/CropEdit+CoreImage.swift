// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import SPFKBase

extension CropEdit {
    /// The kept region of `image`, an upright decode at any scale, corrected by the perspective,
    /// axis-aligned and of ``keptPixelSize(imageWidth:imageHeight:)``, its extent moved to the origin.
    /// The crop is first ``contained(imageWidth:imageHeight:)``, so nothing outside the picture is sampled.
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
        var turned = (crop.hasPerspective ? crop.corrected(image, extent: extent) : image).clampedToExtent()

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

    /// `image` under ``perspective(imageWidth:imageHeight:)``, in the same coordinates.
    ///
    /// `CIPerspectiveTransform` needs a finite input and leaves its edge pixels part transparent, so
    /// the input is padded by one pixel of its own edge and the padded corners are the ones mapped.
    private func corrected(_ image: CIImage, extent: CGRect) -> CIImage {
        let map = perspective(imageWidth: Int(extent.width), imageHeight: Int(extent.height))
        let padded = extent.insetBy(dx: -1, dy: -1)

        // Core Image's y-up point for a point in pixels from the extent's top left, y down, and back.
        func mapped(_ x: CGFloat, _ y: CGFloat) -> CIVector {
            let point = map.apply(SIMD2(Double(x - extent.minX), Double(extent.maxY - y)))
            return CIVector(x: extent.minX + point.x, y: extent.maxY - point.y)
        }

        return image.clampedToExtent().cropped(to: padded).applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": mapped(padded.minX, padded.maxY),
            "inputTopRight": mapped(padded.maxX, padded.maxY),
            "inputBottomRight": mapped(padded.maxX, padded.minY),
            "inputBottomLeft": mapped(padded.minX, padded.minY),
        ])
    }
}
