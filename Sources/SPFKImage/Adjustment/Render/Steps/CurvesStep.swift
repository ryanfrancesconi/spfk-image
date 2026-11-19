// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum CurvesStep {
    /// Entries per channel in the table handed to `CIColorCurves`.
    static let tableCount = 1024

    /// `CIColorCurves` works on sRGB-encoded values only when given this space; without it, on linear.
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    /// A value outside 0…1 continues from the curve's end at 0 or 1 (see ``CIArithmetic/preservingRange(_:in:_:)``).
    static func apply(_ image: CIImage, _ curves: ImageToneCurves) -> CIImage {
        guard !curves.isIdentity else { return image }

        let data = table(curves).withUnsafeBufferPointer { Data(buffer: $0) }

        return CIArithmetic.preservingRange(image) { image in
            let filter = CIFilter.colorCurves()
            filter.inputImage = image
            filter.curvesData = data
            filter.curvesDomain = CIVector(x: 0, y: 1)
            if let colorSpace {
                filter.colorSpace = colorSpace
            }
            return filter.outputImage ?? image
        }
    }

    /// Interleaved red, green and blue outputs at `count` evenly spaced inputs: each channel's curve
    /// applied to the RGB curve's output.
    static func table(_ curves: ImageToneCurves, count: Int = tableCount) -> [Float] {
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
}
