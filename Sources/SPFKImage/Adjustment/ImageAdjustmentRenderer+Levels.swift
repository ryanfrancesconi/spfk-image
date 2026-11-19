// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SPFKBase

extension ImageAdjustmentRenderer {
    /// The part of `adjustments` that renders before the levels step, so its output is what the
    /// levels curve receives. Leaves out noise reduction, which smooths the image without moving its
    /// tones.
    public static func levelsInput(of adjustments: ImageAdjustmentDescription) -> ImageAdjustmentDescription {
        let effective = adjustments.effective

        return ImageAdjustmentDescription(
            light: .init(exposure: effective.light.exposure, blackPoint: effective.light.blackPoint, whitePoint: effective.light.whitePoint),
            color: .init(vibrance: effective.color.vibrance, temperature: effective.color.temperature, tint: effective.color.tint)
        )
    }

    /// The histogram of `source` as the levels step receives it, binned on sRGB-encoded values as the
    /// levels curve reads them: the kept area of `cropEdit` only. Nil when Core Image produces no output.
    public func levelsHistogram(_ adjustments: ImageAdjustmentDescription, cropEdit: CropEdit = CropEdit(), source: CGImage) -> ImageHistogram? {
        histogram(of: source, cropEdit: cropEdit, rendering: Self.levelsInput(of: adjustments))
    }

    /// The histogram of `source`'s kept area with `partial` applied, binned on sRGB-encoded values.
    func histogram(of source: CGImage, cropEdit: CropEdit, rendering partial: ImageAdjustmentDescription) -> ImageHistogram? {
        autoreleasepool {
            let input = Self.apply(partial, to: cropEdit.apply(to: CIImage(cgImage: source)))

            let encoded = CIArithmetic.encodedSRGB(input)

            guard let rgb = bins(of: encoded, extent: input.extent),
                  let luminance = bins(of: CIArithmetic.rec709Luminance(encoded), extent: input.extent)
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
