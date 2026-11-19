// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// A per-pixel color transform rendered through a ``ColorCube``.
///
/// Its stored properties are every input the transform reads: ``ColorCube`` reuses the cached cube
/// whenever a transform compares equal to the one that built it.
protocol ColorCubeTransform: Equatable, Sendable {
    /// The space the transform's nodes and output are encoded in.
    static var space: ColorCubeSpace { get }

    func callAsFunction(_ node: ColorCubeNode) -> SIMD3<Double>
}

extension ColorCubeTransform {
    static var space: ColorCubeSpace { .sRGB }

    /// `rgb`, encoded in ``space``, through the transform.
    func callAsFunction(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        self(Self.space.node(rgb))
    }
}
