// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import os
import simd

/// Color cubes built from a ``ColorCubeTransform``, and the cache holding the last cube of each.
enum ColorCube {
    /// Entries per side of every cube.
    static let dimension = 32

    /// The last cube each transform type built, with the transform it was built from.
    private static let cache = OSAllocatedUnfairLock<[ObjectIdentifier: (transform: any ColorCubeTransform, data: Data)]>(initialState: [:])

    /// `image` through a cube sampling `transform`, in the transform's ``ColorCubeTransform/space``.
    static func apply<T: ColorCubeTransform>(_ transform: T, to image: CIImage) -> CIImage {
        let data = data(for: transform)

        return CIArithmetic.preservingRange(image, in: T.space) { image in
            let filter = CIFilter.colorCubeWithColorSpace()
            filter.inputImage = image
            filter.cubeDimension = Float(dimension)
            filter.cubeData = data
            filter.colorSpace = CGColorSpace(name: T.space.colorSpaceName)
            return filter.outputImage ?? image
        }
    }

    /// The cube for `transform`, rebuilt only when it differs from the last one of its type.
    static func data<T: ColorCubeTransform>(for transform: T) -> Data {
        let key = ObjectIdentifier(T.self)

        if let cached = cache.withLock({ $0[key] }), (cached.transform as? T) == transform {
            return cached.data
        }

        let data = build(nodes: T.space.nodes) { transform($0) }
        cache.withLock { $0[key] = (transform, data) }
        return data
    }

    /// RGBA floats, one per node in `nodes`' order, as `CIColorCube` reads them. Output is clamped
    /// to 0…1.
    static func build(nodes: [ColorCubeNode], _ transform: (ColorCubeNode) -> SIMD3<Double>) -> Data {
        var cube = [Float]()
        cube.reserveCapacity(nodes.count * 4)

        for node in nodes {
            let output = transform(node)
            cube.append(Float(min(max(output.x, 0), 1)))
            cube.append(Float(min(max(output.y, 0), 1)))
            cube.append(Float(min(max(output.z, 0), 1)))
            cube.append(1)
        }

        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Every node of a `dimension` cube encoded in `space`, red varying fastest, then green, then blue.
    static func nodes(dimension: Int = dimension, in space: ColorCubeSpace = .sRGB) -> [ColorCubeNode] {
        let scale = 1 / Double(dimension - 1)
        var nodes = [ColorCubeNode]()
        nodes.reserveCapacity(dimension * dimension * dimension)

        for blue in 0 ..< dimension {
            for green in 0 ..< dimension {
                for red in 0 ..< dimension {
                    nodes.append(space.node(SIMD3(Double(red), Double(green), Double(blue)) * scale))
                }
            }
        }

        return nodes
    }

    /// Built once: the inputs never change.
    static let sRGBNodes = nodes(in: .sRGB)
    static let displayP3Nodes = nodes(in: .displayP3)
}
