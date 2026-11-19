// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import ImageIO
import SPFKBase

extension ImageAdjustmentRenderer {
    /// `kind` for the file at `url`, analyzed at ``autoAnalysisSize`` over `cropEdit`'s kept area with
    /// `orientation` applied. `nil` when it cannot be decoded. Security-scoped access is the caller's.
    public static func autoAdjustments(
        contentsOf url: URL,
        orientation: OrientationEdit = .up,
        cropEdit: CropEdit = CropEdit(),
        kind: ImageAutoAdjustment = .adjust
    ) async -> ImageAdjustmentDescription? {
        let image = autoreleasepool {
            StillImageThumbnail.make(url: url, maxPixelSize: autoAnalysisSize, allowsEmbeddedThumbnail: false)
                .map { orientation.apply(to: cropEdit.apply(to: CIImage(cgImage: $0))) }
        }

        guard let image else { return nil }
        return await kind.analyze(image)
    }

    /// The size the file at `url` displays at, its orientation tag applied, read from its header
    /// without decoding. `nil` when it cannot be read. Security-scoped access is the caller's.
    public static func displayedPixelSize(contentsOf url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int
        else { return nil }

        let orientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1
        let size = ImageFormatConverter.displayedSize(width: width, height: height, orientation: orientation)
        return (size.width, size.height)
    }

    /// The long edge Auto analyzes at, whatever the file's size, so a file gets the same result
    /// alone or in a batch.
    public static let autoAnalysisSize = 1024

    /// Temperature and Tint making a small square around `point` gray, or nil when the point is
    /// outside `image`.
    ///
    /// `point` is in unit coordinates of `image` with the origin at the top left. `image` is the
    /// unadjusted source as shown, oriented: only Exposure renders before the temperature step, and it
    /// does not move hue.
    public static func whiteBalance(sampling point: CGPoint, in image: CIImage) -> (temperature: Double, tint: Double)? {
        WhiteBalanceAnalysis.balance(sampling: point, in: image)
    }
}
