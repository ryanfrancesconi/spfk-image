// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import SPFKTesting
import Testing

@testable import SPFKImage

/// `ImageAdjustmentRenderer.apply` renders in `RenderStep.allCases` order, which the Levels and Curves
/// histogram inputs are derived from, and each step renders from what its `reads` names.
@Suite(.tags(.file))
final class ImageAdjustmentRenderOrderingTests {
    typealias Description = ImageAdjustmentDescription

    let context = CIContext()
    let input: CIImage

    init() throws {
        let songbird = CIImage(cgImage: try CGImage.contentsOf(url: TestBundleResources.shared.songbird))
        input = songbird.transformed(by: CGAffineTransform(scaleX: 0.2, y: 0.2))
    }

    static let adjacentPairs = Array(zip(RenderStep.allCases, RenderStep.allCases.dropFirst()))

    /// Pairs whose two orders render the same, so a render cannot tell which ran first: a gain and a
    /// color matrix.
    static let commuting: [(RenderStep, RenderStep)] = [(.exposure, .whiteBalance)]

    /// A render of two steps at once matches the first step's render fed to the second, and not the
    /// reverse.
    @Test(arguments: adjacentPairs)
    func applyRunsEachAdjacentPairInRenderStepOrder(first: RenderStep, second: RenderStep) throws {
        let firstOnly = Self.description(of: [first])
        let secondOnly = Self.description(of: [second])

        let together = try pixels(ImageAdjustmentRenderer.apply(Self.description(of: [first, second]), to: input))
        let inOrder = try pixels(
            ImageAdjustmentRenderer.apply(secondOnly, to: ImageAdjustmentRenderer.apply(firstOnly, to: input))
        )
        let reversed = try pixels(
            ImageAdjustmentRenderer.apply(firstOnly, to: ImageAdjustmentRenderer.apply(secondOnly, to: input))
        )

        let orderDifference = Self.maximumDifference(inOrder, reversed)
        let fromInOrder = Self.maximumDifference(together, inOrder)

        if Self.commuting.contains(where: { $0 == (first, second) }) {
            #expect(orderDifference < Self.tolerance)
        } else {
            #expect(orderDifference > Self.minimumOrderDifference)
        }

        #expect(fromInOrder < Self.tolerance)
    }

    /// Every parameter and every section is read by exactly one step, so a step's place in the order
    /// places everything it reads.
    @Test func everyParameterAndSectionBelongsToOneStep() {
        var parameters = [Description.Parameter]()
        var groups = [Description.Group]()

        for step in RenderStep.allCases {
            switch step.reads {
            case let .parameters(read): parameters += read
            case let .group(group): groups.append(group)
            }
        }

        let viaGroups = groups.flatMap(\.parameters)
        let all = parameters + viaGroups

        #expect(Set(all).count == all.count)
        #expect(Set(all) == Set(Description.Parameter.allCases))
        #expect(Set(groups).count == groups.count)
        #expect(groups.contains(.curves))
    }

    /// The histogram inputs hold what renders before their step, without noise reduction.
    @Test func theHistogramInputsHoldWhatRendersBeforeTheirStep() {
        let everything = Self.description(of: RenderStep.allCases)

        let beforeLevels = Description(
            light: .init(
                exposure: everything.light.exposure,
                blackPoint: everything.light.blackPoint,
                whitePoint: everything.light.whitePoint
            ),
            color: .init(
                vibrance: everything.color.vibrance,
                temperature: everything.color.temperature,
                tint: everything.color.tint
            )
        )
        var beforeCurves = beforeLevels
        beforeCurves.levels = everything.levels

        #expect(ImageAdjustmentRenderer.levelsInput(of: everything) == beforeLevels)
        #expect(ImageAdjustmentRenderer.curvesInput(of: everything) == beforeCurves)
    }

    // MARK: - Helpers

    /// In linear values. The chained renders build the same filter graph as the single one.
    static let tolerance: Float = 1e-3
    /// What two orders of a pair that does not commute differ by, at least, in linear values.
    static let minimumOrderDifference: Float = 1e-2

    /// A description with only `steps` away from neutral, each far enough to show.
    static func description(of steps: [RenderStep]) -> Description {
        var result = Description()

        for step in steps {
            switch step {
            case .noiseReduction: result.detail.noiseReduction = 1
            case .exposure: result.light.exposure = 0.8
            case .whiteBalance:
                result.color.temperature = 0.5
                result.color.tint = -0.4
            case .vibrance: result.color.vibrance = 0.8
            case .blackPoint: result.light.blackPoint = 0.6
            case .whitePoint: result.light.whitePoint = 0.6
            case .levels: result.levels = .init(black: 0.1, mid: 0.2, white: -0.15)
            case .curves:
                result.curves.rgb = [.init(x: 0, y: 0), .init(x: 0.3, y: 0.5), .init(x: 1, y: 1)]
                result.curves.red = [.init(x: 0, y: 0.1), .init(x: 1, y: 0.8)]
            case .highlightsShadows:
                result.light.highlights = -0.7
                result.light.shadows = 0.7
            case .brightness: result.light.brightness = 0.6
            case .brilliance: result.light.brilliance = 0.8
            case .contrast: result.light.contrast = 0.7
            case .saturation: result.color.saturation = 0.7
            case .definition: result.detail.definition = 0.9
            case .selectiveColor:
                result.selectiveColor.red = .init(hue: 0.7, saturation: -0.5, luminance: 0.4)
                result.selectiveColor.green = .init(hue: -0.6, saturation: 0.6, luminance: -0.4)
                result.selectiveColor.blue = .init(hue: 0.5, saturation: 0.5, luminance: 0.5)
            case .blackAndWhite:
                result.blackAndWhite.isOn = true
                result.blackAndWhite.red = 0.8
                result.blackAndWhite.green = -0.6
            case .colorGrading:
                result.colorGrading.shadows = .init(hue: 0.6, saturation: 0.8)
                result.colorGrading.highlights = .init(hue: 0.1, saturation: 0.8)
            case .sepia: result.color.sepia = 0.8
            case .sharpness:
                result.detail.sharpness = 1
                result.detail.sharpnessRadius = 0.5
            case .vignette: result.vignette = .init(amount: 0.9, radius: -0.5)
            case .grain: result.grain.amount = 0.9
            }
        }

        return result
    }

    /// `image` in extended linear sRGB.
    func pixels(_ image: CIImage) throws -> [Float] {
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let rendered = try #require(
            context.createCGImage(image, from: image.extent, format: .RGBAf, colorSpace: space, deferred: false)
        )
        let data = try #require(rendered.dataProvider?.data) as Data
        let rowFloats = rendered.width * 4

        return data.withUnsafeBytes { buffer in
            (0 ..< rendered.height).flatMap { row in
                let start = buffer.baseAddress?.advanced(by: row * rendered.bytesPerRow)
                return Array(UnsafeBufferPointer(start: start?.assumingMemoryBound(to: Float.self), count: rowFloats))
            }
        }
    }

    static func maximumDifference(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return .infinity }
        return zip(a, b).map { abs($0 - $1) }.max() ?? 0
    }
}
