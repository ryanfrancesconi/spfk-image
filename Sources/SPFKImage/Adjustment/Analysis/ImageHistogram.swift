// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// An image's tonal distribution in ``binCount`` bins over sRGB-encoded values, black first. Each
/// channel's bins hold shares of the image's pixels and sum to 1.
public struct ImageHistogram: Hashable, Sendable {
    public static let binCount = 256

    public var red: [Float]
    public var green: [Float]
    public var blue: [Float]
    /// Rec. 709 luma of the encoded values.
    public var luminance: [Float]

    public init(red: [Float], green: [Float], blue: [Float], luminance: [Float]) {
        self.red = red
        self.green = green
        self.blue = blue
        self.luminance = luminance
    }
}

extension ImageHistogram {
    /// `CIAreaHistogram`'s RGBA shares of `image` over `extent`, rendered by `context`. Read back without
    /// color management: the values are counts.
    static func bins(of image: CIImage, extent: CGRect, context: CIContext) -> [SIMD4<Float>]? {
        let filter = CIFilter.areaHistogram()
        filter.inputImage = image
        filter.extent = extent
        filter.count = binCount
        filter.scale = 1
        guard let output = filter.outputImage else { return nil }

        var bins = [SIMD4<Float>](repeating: .zero, count: binCount)
        bins.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            context.render(
                output,
                toBitmap: base,
                rowBytes: binCount * MemoryLayout<SIMD4<Float>>.stride,
                bounds: CGRect(x: 0, y: 0, width: binCount, height: 1),
                format: .RGBAf,
                colorSpace: nil
            )
        }
        return bins
    }
}
