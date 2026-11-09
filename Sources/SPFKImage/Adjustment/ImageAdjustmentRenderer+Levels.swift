// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

extension ImageAdjustmentRenderer {
    /// The levels points as `CIToneCurve` points: each ordered input position to its fixed output.
    static func levelsCurve(_ adjustments: ImageAdjustmentDescription) -> [CGPoint] {
        zip(adjustments.levelsPositions, ImageAdjustmentDescription.levelsIdentity).map { CGPoint(x: $0, y: $1) }
    }

    /// The part of `adjustments` that renders before the levels step, so its output is what the
    /// levels curve receives. Leaves out noise reduction, which smooths the image without moving its
    /// tones.
    public static func levelsInput(of adjustments: ImageAdjustmentDescription) -> ImageAdjustmentDescription {
        let effective = adjustments.effective

        return ImageAdjustmentDescription(
            exposure: effective.exposure,
            blackPoint: effective.blackPoint,
            whitePoint: effective.whitePoint,
            vibrance: effective.vibrance,
            temperature: effective.temperature,
            tint: effective.tint
        )
    }

    /// The histogram of `source` as the levels step receives it, binned on sRGB-encoded values as the
    /// levels curve reads them. Nil when Core Image produces no output.
    public func levelsHistogram(_ adjustments: ImageAdjustmentDescription, source: CGImage) -> ImageHistogram? {
        histogram(of: source, rendering: Self.levelsInput(of: adjustments))
    }

    /// The histogram of `source` with `partial` applied, binned on sRGB-encoded values.
    func histogram(of source: CGImage, rendering partial: ImageAdjustmentDescription) -> ImageHistogram? {
        autoreleasepool {
            let input = Self.apply(partial, to: CIImage(cgImage: source))

            let encode = CIFilter.linearToSRGBToneCurve()
            encode.inputImage = input
            guard let encoded = encode.outputImage else { return nil }

            let luma = CIFilter.colorMatrix()
            luma.inputImage = encoded
            let weights = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
            luma.rVector = weights
            luma.gVector = weights
            luma.bVector = weights
            luma.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)

            guard let lumaImage = luma.outputImage,
                  let rgb = bins(of: encoded, extent: input.extent),
                  let luminance = bins(of: lumaImage, extent: input.extent)
            else { return nil }

            return ImageHistogram(
                red: rgb.map(\.x),
                green: rgb.map(\.y),
                blue: rgb.map(\.z),
                luminance: luminance.map(\.x)
            )
        }
    }

    /// `CIAreaHistogram`'s RGBA shares. Read back without color management: the values are counts.
    private func bins(of image: CIImage, extent: CGRect) -> [SIMD4<Float>]? {
        let filter = CIFilter.areaHistogram()
        filter.inputImage = image
        filter.extent = extent
        filter.count = ImageHistogram.binCount
        filter.scale = 1
        guard let output = filter.outputImage else { return nil }

        var bins = [SIMD4<Float>](repeating: .zero, count: ImageHistogram.binCount)
        bins.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            context.render(
                output,
                toBitmap: base,
                rowBytes: ImageHistogram.binCount * MemoryLayout<SIMD4<Float>>.stride,
                bounds: CGRect(x: 0, y: 0, width: ImageHistogram.binCount, height: 1),
                format: .RGBAf,
                colorSpace: nil
            )
        }
        return bins
    }
}
