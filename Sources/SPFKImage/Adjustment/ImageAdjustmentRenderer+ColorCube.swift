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
        colorCube(image, data: colorCubeData(step: step, values: values, transform: transform))
    }

    /// ``colorCube(_:step:values:transform:)`` for a transform reading each node's precomputed
    /// ``ColorCubeNode`` rather than converting its color on every build.
    static func colorCube(
        _ image: CIImage,
        step: String,
        values: [Double],
        nodeTransform: (ColorCubeNode) -> SIMD3<Double>
    ) -> CIImage {
        colorCube(image, data: colorCubeData(step: step, values: values) { buildColorCube(nodeTransform: nodeTransform) })
    }

    private static func colorCube(_ image: CIImage, data: Data) -> CIImage {
        preservingRange(image) { image in
            let filter = CIFilter.colorCubeWithColorSpace()
            filter.inputImage = image
            filter.cubeDimension = Float(colorCubeDimension)
            filter.cubeData = data
            filter.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            return filter.outputImage ?? image
        }
    }

    static func colorCubeData(step: String, values: [Double], transform: ColorTransform) -> Data {
        colorCubeData(step: step, values: values) { buildColorCube(dimension: colorCubeDimension, transform: transform) }
    }

    private static func colorCubeData(step: String, values: [Double], build: () -> Data) -> Data {
        if let cached = colorCubeCache.withLock({ $0[step] }), cached.values == values {
            return cached.data
        }

        let data = build()
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
                    append(transform(SIMD3(Double(red), Double(green), Double(blue)) * scale), to: &cube)
                }
            }
        }

        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func buildColorCube(nodeTransform: (ColorCubeNode) -> SIMD3<Double>) -> Data {
        var cube = [Float]()
        cube.reserveCapacity(colorCubeNodes.count * 4)

        for node in colorCubeNodes {
            append(nodeTransform(node), to: &cube)
        }

        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func append(_ output: SIMD3<Double>, to cube: inout [Float]) {
        cube.append(Float(min(max(output.x, 0), 1)))
        cube.append(Float(min(max(output.y, 0), 1)))
        cube.append(Float(min(max(output.z, 0), 1)))
        cube.append(1)
    }

    /// Every node of a ``colorCubeDimension`` cube, in cube order. Built once: the inputs never change.
    static let colorCubeNodes: [ColorCubeNode] = {
        let scale = 1 / Double(colorCubeDimension - 1)
        var nodes = [ColorCubeNode]()
        nodes.reserveCapacity(colorCubeDimension * colorCubeDimension * colorCubeDimension)

        for blue in 0 ..< colorCubeDimension {
            for green in 0 ..< colorCubeDimension {
                for red in 0 ..< colorCubeDimension {
                    nodes.append(ColorCubeNode(SIMD3(Double(red), Double(green), Double(blue)) * scale))
                }
            }
        }

        return nodes
    }()
}

/// One sRGB-encoded color with the coordinates the hue-based steps read.
struct ColorCubeNode: Sendable {
    let rgb: SIMD3<Double>
    let oklab: SIMD3<Double>
    /// Oklch hue in degrees, 0…360.
    let hue: Double
    /// Max − min of the sRGB-encoded channels.
    let chroma: Double

    init(_ rgb: SIMD3<Double>) {
        self.rgb = rgb
        oklab = ImageAdjustmentRenderer.oklab(rgb)
        hue = ImageAdjustmentRenderer.oklchHue(oklab)
        chroma = rgb.max() - rgb.min()
    }
}
