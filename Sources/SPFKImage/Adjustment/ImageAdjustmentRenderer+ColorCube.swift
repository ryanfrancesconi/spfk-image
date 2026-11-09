// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import os

extension ImageAdjustmentRenderer {
    /// A per-pixel color transform on sRGB-encoded red, green and blue in 0…1.
    typealias ColorTransform = (SIMD3<Double>) -> SIMD3<Double>

    /// Entries per side of every color cube.
    static let colorCubeDimension = 32

    /// The last cube each step built, by the step's name, with the values it was built from.
    private static let colorCubeCache = OSAllocatedUnfairLock<[String: (values: [Double], data: Data)]>(initialState: [:])

    /// `image` through a color cube sampling `transform`. The cube is rebuilt only when `values`, the
    /// inputs `transform` depends on, differ from the last build for `step`. A value outside 0…1 takes
    /// the change its clamped value would.
    static func colorCube(
        _ image: CIImage,
        step: String,
        values: [Double],
        transform: ColorTransform
    ) -> CIImage {
        let data = colorCubeData(step: step, values: values, transform: transform)

        return preservingRange(image) { image in
            let filter = CIFilter.colorCubeWithColorSpace()
            filter.inputImage = image
            filter.cubeDimension = Float(colorCubeDimension)
            filter.cubeData = data
            filter.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            return filter.outputImage ?? image
        }
    }

    static func colorCubeData(step: String, values: [Double], transform: ColorTransform) -> Data {
        if let cached = colorCubeCache.withLock({ $0[step] }), cached.values == values {
            return cached.data
        }

        let data = buildColorCube(dimension: colorCubeDimension, transform: transform)
        colorCubeCache.withLock { $0[step] = (values, data) }
        return data
    }

    /// RGBA floats, red varying fastest, then green, then blue, as `CIColorCube` reads them.
    static func buildColorCube(dimension: Int, transform: ColorTransform) -> Data {
        var cube = [Float]()
        cube.reserveCapacity(dimension * dimension * dimension * 4)
        let scale = 1 / Double(dimension - 1)

        for blue in 0 ..< dimension {
            for green in 0 ..< dimension {
                for red in 0 ..< dimension {
                    let output = transform(SIMD3(Double(red), Double(green), Double(blue)) * scale)
                    cube.append(Float(min(max(output.x, 0), 1)))
                    cube.append(Float(min(max(output.y, 0), 1)))
                    cube.append(Float(min(max(output.z, 0), 1)))
                    cube.append(1)
                }
            }
        }

        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
