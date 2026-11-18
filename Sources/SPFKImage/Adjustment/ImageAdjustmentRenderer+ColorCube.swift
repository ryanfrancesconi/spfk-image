// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import os
import simd

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
    /// ``ColorCubeNode`` rather than converting its color on every build. In `space`, the nodes and the
    /// transform's output are encoded in that space and span its gamut.
    static func colorCube(
        _ image: CIImage,
        step: String,
        values: [Double],
        space: ColorCubeSpace = .sRGB,
        nodeTransform: (ColorCubeNode) -> SIMD3<Double>
    ) -> CIImage {
        let data = colorCubeData(step: step, values: values) { buildColorCube(nodes: space.nodes, nodeTransform: nodeTransform) }
        return colorCube(image, data: data, space: space)
    }

    private static func colorCube(_ image: CIImage, data: Data, space: ColorCubeSpace = .sRGB) -> CIImage {
        preservingRange(image, in: space) { image in
            let filter = CIFilter.colorCubeWithColorSpace()
            filter.inputImage = image
            filter.cubeDimension = Float(colorCubeDimension)
            filter.cubeData = data
            filter.colorSpace = CGColorSpace(name: space.colorSpaceName)
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

    private static func buildColorCube(nodes: [ColorCubeNode], nodeTransform: (ColorCubeNode) -> SIMD3<Double>) -> Data {
        var cube = [Float]()
        cube.reserveCapacity(nodes.count * 4)

        for node in nodes {
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

    /// Every node of a ``colorCubeDimension`` cube, sRGB-encoded, in cube order. Built once: the inputs
    /// never change.
    static let colorCubeNodes = cubeNodes { ColorCubeNode($0) }

    /// ``colorCubeNodes`` Display P3-encoded.
    static let displayP3ColorCubeNodes = cubeNodes { ColorCubeNode(displayP3: $0) }

    private static func cubeNodes(_ node: (SIMD3<Double>) -> ColorCubeNode) -> [ColorCubeNode] {
        let scale = 1 / Double(colorCubeDimension - 1)
        var nodes = [ColorCubeNode]()
        nodes.reserveCapacity(colorCubeDimension * colorCubeDimension * colorCubeDimension)

        for blue in 0 ..< colorCubeDimension {
            for green in 0 ..< colorCubeDimension {
                for red in 0 ..< colorCubeDimension {
                    nodes.append(node(SIMD3(Double(red), Double(green), Double(blue)) * scale))
                }
            }
        }

        return nodes
    }
}

/// The color space a node-based cube is encoded in.
enum ColorCubeSpace {
    case sRGB
    case displayP3

    var nodes: [ColorCubeNode] {
        switch self {
        case .sRGB: ImageAdjustmentRenderer.colorCubeNodes
        case .displayP3: ImageAdjustmentRenderer.displayP3ColorCubeNodes
        }
    }

    var colorSpaceName: CFString {
        switch self {
        case .sRGB: CGColorSpace.sRGB
        case .displayP3: CGColorSpace.displayP3
        }
    }
}

/// One encoded color with the coordinates the hue-based steps read.
struct ColorCubeNode: Sendable {
    let rgb: SIMD3<Double>
    let oklab: SIMD3<Double>
    /// Oklch hue in degrees, 0…360.
    let hue: Double
    /// Max − min of the encoded channels.
    let chroma: Double

    /// An sRGB-encoded color.
    init(_ rgb: SIMD3<Double>) {
        self.init(rgb, linearSRGB: Self.decoded(rgb))
    }

    /// A Display P3-encoded color.
    init(displayP3 rgb: SIMD3<Double>) {
        self.init(rgb, linearSRGB: ImageAdjustmentRenderer.displayP3ToLinearSRGB * Self.decoded(rgb))
    }

    private init(_ rgb: SIMD3<Double>, linearSRGB: SIMD3<Double>) {
        self.rgb = rgb
        oklab = ImageAdjustmentRenderer.oklab(linear: linearSRGB)
        hue = ImageAdjustmentRenderer.oklchHue(oklab)
        chroma = rgb.max() - rgb.min()
    }

    private static func decoded(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            ImageAdjustmentRenderer.sRGBDecoded(rgb.x),
            ImageAdjustmentRenderer.sRGBDecoded(rgb.y),
            ImageAdjustmentRenderer.sRGBDecoded(rgb.z)
        )
    }
}
