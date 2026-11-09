// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

extension ImageAdjustmentRenderer {
    /// Entries per channel in the table handed to `CIColorCurves`.
    static let curvesTableCount = 1024

    /// `CIColorCurves` works on sRGB-encoded values only when given this space; without it, on linear.
    private static let curvesColorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    static func curves(_ image: CIImage, _ curves: ImageToneCurves) -> CIImage {
        let filter = CIFilter.colorCurves()
        filter.inputImage = image
        filter.curvesData = curvesTable(curves).withUnsafeBufferPointer { Data(buffer: $0) }
        filter.curvesDomain = CIVector(x: 0, y: 1)
        if let curvesColorSpace {
            filter.colorSpace = curvesColorSpace
        }
        return filter.outputImage ?? image
    }

    /// Interleaved red, green and blue outputs at `count` evenly spaced inputs: each channel's curve
    /// applied to the RGB curve's output.
    static func curvesTable(_ curves: ImageToneCurves, count: Int = curvesTableCount) -> [Float] {
        let rgb = curves.interpolation(.rgb).sample(count: count)

        let channels: [[Double]] = [ImageToneCurves.Channel.red, .green, .blue].map { channel in
            guard curves[channel] != ImageToneCurves.identityPoints else { return rgb }
            let curve = curves.interpolation(channel)
            return rgb.map(curve.value(at:))
        }

        var table = [Float]()
        table.reserveCapacity(count * 3)

        for index in 0 ..< count {
            for channel in channels {
                table.append(Float(min(max(channel[index], 0), 1)))
            }
        }

        return table
    }

    /// The part of `adjustments` that renders before the curves step: the levels input and levels.
    public static func curvesInput(of adjustments: ImageAdjustmentDescription) -> ImageAdjustmentDescription {
        var input = levelsInput(of: adjustments)
        input.levels = adjustments.effective.levels
        return input
    }

    /// The histogram of `source` as the curves step receives it, binned on sRGB-encoded values as the
    /// curves read them. Nil when Core Image produces no output.
    public func curvesHistogram(_ adjustments: ImageAdjustmentDescription, source: CGImage) -> ImageHistogram? {
        histogram(of: source, rendering: Self.curvesInput(of: adjustments))
    }
}
