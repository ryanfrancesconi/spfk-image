// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreGraphics
import Foundation

/// The color space a cube is encoded in. A cube's nodes and its transform's output are encoded in it
/// and span its gamut.
enum ColorCubeSpace {
    case sRGB
    case displayP3

    var nodes: [ColorCubeNode] {
        switch self {
        case .sRGB: ColorCube.sRGBNodes
        case .displayP3: ColorCube.displayP3Nodes
        }
    }

    var colorSpaceName: CFString {
        switch self {
        case .sRGB: CGColorSpace.sRGB
        case .displayP3: CGColorSpace.displayP3
        }
    }

    /// The node for `rgb`, encoded in this space.
    func node(_ rgb: SIMD3<Double>) -> ColorCubeNode {
        switch self {
        case .sRGB: ColorCubeNode(rgb)
        case .displayP3: ColorCubeNode(displayP3: rgb)
        }
    }
}
