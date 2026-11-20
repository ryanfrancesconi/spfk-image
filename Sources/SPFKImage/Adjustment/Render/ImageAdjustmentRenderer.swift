// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import SPFKBase

/// Applies an ``ImageAdjustmentDescription`` to an image through Core Image.
///
/// Holds one `CIContext` to reuse: a new context per render costs more than the filter chain. Filters
/// are built inside each call and never leave it, since `CIFilter` is not `Sendable` and the context
/// and images are.
public struct ImageAdjustmentRenderer: Sendable {
    public let context: CIContext

    public init(context: CIContext = CIContext()) {
        self.context = context
    }

    /// `image` with `adjustments` applied in `RenderStep` order, cropped to the input's extent. Lazy:
    /// nothing renders until the result is drawn.
    ///
    /// `sourceScale` is `image`'s size relative to the full-resolution source (see
    /// ``sourceScale(of:fullWidth:fullHeight:)``), so a filter sized in pixels looks the same on a
    /// downsampled preview as in the saved file. `grainSeed` picks the grain's pattern; a video passes
    /// its frame index so the grain moves from frame to frame.
    public static func apply(
        _ adjustments: ImageAdjustmentDescription,
        to image: CIImage,
        sourceScale: Double = 1,
        grainSeed: Int64 = 0
    ) -> CIImage {
        let adjustments = adjustments.effective
        guard !adjustments.isEmpty else { return image }

        let frame = RenderFrame(extent: image.extent, sourceScale: sourceScale, grainSeed: grainSeed)

        return RenderStep.allCases
            .reduce(image) { output, step in step.apply(output, adjustments, frame) }
            .cropped(to: image.extent)
    }

    /// Renders `source` cropped by `cropEdit`, then with `adjustments`, then `orientation`, into a
    /// bitmap in the source's color space and bit depth.
    ///
    /// With `region`, only that part of the cropped, oriented output renders, in its pixels with the
    /// origin at the top left, expanded to whole pixels and limited to the output. The adjustments
    /// still see the whole kept area, so a region matches the same part cut from a full render.
    /// `sourceScale` is computed from the uncropped `source`.
    ///
    /// Eager (`deferred: false`), so the cost lands here rather than wherever the image is first drawn.
    public func render(
        _ adjustments: ImageAdjustmentDescription,
        orientation: OrientationEdit = .up,
        cropEdit: CropEdit = CropEdit(),
        source: CGImage,
        sourceScale: Double = 1,
        region: CGRect? = nil
    ) -> CGImage? {
        autoreleasepool {
            let cropped = cropEdit.apply(to: CIImage(cgImage: source))
            let adjusted = Self.apply(adjustments, to: cropped, sourceScale: sourceScale)
            let output = orientation.apply(to: adjusted)
            let rendered = region.map { Self.coreImageRect(topLeft: $0, in: output.extent) } ?? output.extent

            guard !rendered.isEmpty else { return nil }

            return context.createCGImage(
                output,
                from: rendered,
                format: source.bitsPerComponent > 8 ? .RGBA16 : .RGBA8,
                colorSpace: Self.renderColorSpace(for: source),
                deferred: false
            )
        }
    }

    /// `rect`, with its origin at the top left of `extent`, in Core Image's bottom-left coordinates,
    /// expanded to whole pixels and limited to `extent`.
    static func coreImageRect(topLeft rect: CGRect, in extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + rect.minX,
            y: extent.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        ).integral.intersection(extent)
    }

    /// The scale of an image `extent` decoded from a source of `fullWidth` × `fullHeight` pixels, or 1
    /// when either is unknown. Compares the longer sides, so an upright decode of a rotated file still
    /// matches its unoriented pixel dimensions.
    public static func sourceScale(of extent: CGRect, fullWidth: Int?, fullHeight: Int?) -> Double {
        guard let fullWidth, let fullHeight, max(fullWidth, fullHeight) > 0 else { return 1 }
        return Double(max(extent.width, extent.height)) / Double(max(fullWidth, fullHeight))
    }

    /// The source's color space when it is RGB, which `createCGImage` requires; sRGB otherwise.
    public static func renderColorSpace(for image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb {
            return space
        }

        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }
}
