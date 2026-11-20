// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreGraphics
import CoreImage
import Foundation
import SPFKBase

extension StillImageThumbnail {
    /// `url` developed through `recipe`, upright, in 8-bit sRGB, its long edge `maxPixelSize` or the
    /// image's own when smaller. Throws for a file that is not RAW or that the develop refuses.
    ///
    /// A RAW render blocks its thread on work needing a cooperative thread, so it runs under a
    /// ``BlockingCallLimiter/shared`` slot. A decoder version this system lacks develops with the default.
    public static func developed(url: URL, maxPixelSize: Int, recipe: StillThumbnailRecipe) async throws -> CGImage {
        try await BlockingCallLimiter.shared.run {
            try Task.checkCancellation()

            return try autoreleasepool {
                try render(url: url, maxPixelSize: maxPixelSize, recipe: recipe)
            }
        }
    }

    private static let developContext = CIContext(options: [.cacheIntermediates: false])

    private static func render(url: URL, maxPixelSize: Int, recipe: StillThumbnailRecipe) throws -> CGImage {
        let session = try developSession(url: url, decoderVersion: recipe.decoderVersion)

        let native = session.nativeSize
        let longSide = max(native.width, native.height)
        guard longSide > 0, maxPixelSize > 0 else { throw RAWDevelopError.developFailed }

        let scale = min(1, Double(maxPixelSize) / Double(longSide))
        let developed = try session.develop(recipe.adjustments, options: RAWDevelop.Options(scaleFactor: scale))

        let sourceScale = ImageAdjustmentRenderer.sourceScale(
            of: developed.image.extent, fullWidth: Int(native.width), fullHeight: Int(native.height)
        )
        let image = ImageAdjustmentRenderer.apply(developed.remaining, to: developed.image, sourceScale: sourceScale)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let cgImage = developContext.createCGImage(
                  image, from: image.extent, format: .RGBA8, colorSpace: colorSpace, deferred: false
              )
        else { throw RAWDevelopError.developFailed }

        return cgImage
    }

    private static func developSession(url: URL, decoderVersion: String?) throws -> RAWDevelop.Session {
        do {
            return try RAWDevelop.Session(contentsOf: url, decoderVersion: decoderVersion)
        } catch let RAWDevelopError.unsupportedDecoderVersion(version) {
            Log.error(
                "\(url.lastPathComponent) was adjusted with RAW decoder version \(version), which this Mac does not offer; using the default"
            )
            return try RAWDevelop.Session(contentsOf: url)
        }
    }
}
