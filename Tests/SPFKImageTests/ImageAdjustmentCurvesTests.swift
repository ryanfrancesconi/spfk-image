// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreGraphics
import CoreImage
import Foundation
@testable import SPFKImage
import Testing

@Suite
struct ImageAdjustmentCurvesTests {
    typealias Point = ImageToneCurves.Point

    /// A 256 × 1 sRGB gray ramp, one 8-bit level per pixel.
    private func ramp() throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: 256 * 4)
        for level in 0 ..< 256 {
            bytes[level * 4] = UInt8(level)
            bytes[level * 4 + 1] = UInt8(level)
            bytes[level * 4 + 2] = UInt8(level)
        }

        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))

        return try #require(CGImage(
            width: 256, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 256 * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    /// The ramp rendered with `curves`, as RGBA bytes per level.
    private func render(_ curves: ImageToneCurves, bypassed: Bool = false) throws -> [[Int]] {
        let output = try #require(ImageAdjustmentRenderer().render(
            ImageAdjustmentDescription(curves: curves, curvesBypassed: bypassed),
            source: try ramp()
        ))

        let data = try #require(output.dataProvider?.data) as Data
        let rowBytes = output.bytesPerRow
        #expect(output.bitsPerComponent == 8)

        return (0 ..< 256).map { level in
            (0 ..< 3).map { Int(data[rowBytes * 0 + level * 4 + $0]) }
        }
    }

    // MARK: - Rendering

    @Test func aCurveOnTheDiagonalRendersTheRampUnchanged() throws {
        let pixels = try render(ImageToneCurves(rgb: [Point(x: 0, y: 0), Point(x: 0.5, y: 0.5), Point(x: 1, y: 1)]))

        for (level, rgb) in pixels.enumerated() {
            #expect(rgb.allSatisfy { abs($0 - level) <= 1 }, "level \(level): \(rgb)")
        }
    }

    @Test func aCurveThroughAPointMapsThatGrayToItsOutput() throws {
        let pixels = try render(ImageToneCurves(rgb: [Point(x: 0, y: 0), Point(x: 0.5, y: 0.75), Point(x: 1, y: 1)]))
        let expected = 0.75 * 255

        // Level 128 is 0.502, a step past the point.
        #expect(pixels[128].allSatisfy { abs(Double($0) - expected) <= 2 }, "\(pixels[128])")
    }

    @Test func aChannelCurveMovesOnlyItsChannel() throws {
        let pixels = try render(ImageToneCurves(red: [Point(x: 0, y: 0), Point(x: 0.5, y: 0.75), Point(x: 1, y: 1)]))

        #expect(pixels[128][0] > 180)
        #expect(abs(pixels[128][1] - 128) <= 1)
        #expect(abs(pixels[128][2] - 128) <= 1)
    }

    @Test func aChannelCurveActsOnTheRGBCurvesOutput() throws {
        let curves = ImageToneCurves(
            rgb: [Point(x: 0, y: 0), Point(x: 0.5, y: 0.75), Point(x: 1, y: 1)],
            red: [Point(x: 0, y: 1), Point(x: 1, y: 0)]
        )
        let pixels = try render(curves)

        // Red inverts the RGB curve's 0.75; green and blue keep it.
        #expect(abs(Double(pixels[128][0]) - 0.25 * 255) <= 2, "\(pixels[128])")
        #expect(abs(Double(pixels[128][1]) - 0.75 * 255) <= 2, "\(pixels[128])")
    }

    @Test func endsMovedInwardClipBeyondThem() throws {
        let pixels = try render(ImageToneCurves(rgb: [Point(x: 0.25, y: 0), Point(x: 0.75, y: 1)]))

        #expect(pixels[32] == [0, 0, 0])
        #expect(pixels[224] == [255, 255, 255])
    }

    @Test func bypassedCurvesRenderUnchangedAndKeepTheirPoints() throws {
        let curves = ImageToneCurves(rgb: [Point(x: 0, y: 0), Point(x: 0.5, y: 0.75), Point(x: 1, y: 1)])
        let pixels = try render(curves, bypassed: true)

        #expect(abs(pixels[128][0] - 128) <= 1)

        let adjustments = ImageAdjustmentDescription(curves: curves, curvesBypassed: true)
        #expect(adjustments.effective.isEmpty)
        #expect(!adjustments.isEmpty)
        #expect(adjustments.unrenderedPart == adjustments)
    }

    @Test func aSwitchedOffIdentityCurveIsStillStored() {
        let adjustments = ImageAdjustmentDescription(curvesBypassed: true)

        #expect(!adjustments.isEmpty)
        #expect(adjustments.effective.isEmpty)
    }

    @Test func theCurvesHistogramIncludesLevels() throws {
        let renderer = ImageAdjustmentRenderer()
        let adjustments = ImageAdjustmentDescription(levelsBlack: 0.3)

        let levels = try #require(renderer.levelsHistogram(adjustments, source: try ramp()))
        let curves = try #require(renderer.curvesHistogram(adjustments, source: try ramp()))

        #expect(levels.luminance[0] < 0.05)
        #expect(curves.luminance[0] > 0.25)
    }

    // MARK: - Interpolation

    private static let pointSets: [[Point]] = [
        [Point(x: 0, y: 0), Point(x: 0.3, y: 0.05), Point(x: 0.35, y: 0.9), Point(x: 1, y: 1)],
        [Point(x: 0, y: 0.1), Point(x: 0.2, y: 0.2), Point(x: 0.21, y: 0.2), Point(x: 0.6, y: 0.95), Point(x: 0.9, y: 1)],
        [Point(x: 0.1, y: 0), Point(x: 0.5, y: 0.5), Point(x: 0.52, y: 0.98), Point(x: 0.55, y: 1)],
    ]

    @Test(arguments: pointSets)
    func increasingPointsGiveACurveInsideTheRangeThatNeverDecreases(points: [Point]) {
        let curve = MonotoneCubicInterpolation(x: points.map(\.x), y: points.map(\.y))
        let samples = curve.sample(count: 2048)

        #expect(samples.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 + 1e-12 })
    }

    @Test(arguments: pointSets)
    func theCurvePassesThroughItsPointsAndIsFlatBeyondTheEnds(points: [Point]) throws {
        let curve = MonotoneCubicInterpolation(x: points.map(\.x), y: points.map(\.y))

        for point in points {
            #expect(abs(curve.value(at: point.x) - point.y) < 1e-9)
        }

        let first = try #require(points.first)
        let last = try #require(points.last)
        #expect(curve.value(at: first.x / 2) == first.y)
        #expect(curve.value(at: (last.x + 1) / 2) == last.y)
    }

    @Test func sampledAndPointwiseValuesAgree() {
        let points = Self.pointSets[0]
        let curve = MonotoneCubicInterpolation(x: points.map(\.x), y: points.map(\.y))
        let samples = curve.sample(count: 101)

        for (index, sample) in samples.enumerated() {
            #expect(abs(sample - curve.value(at: Double(index) / 100)) < 1e-12)
        }
    }

    @Test func aFallingPointStaysBetweenItsNeighbors() {
        let curve = MonotoneCubicInterpolation(x: [0, 0.4, 0.6, 1], y: [0, 0.9, 0.2, 1])
        let samples = curve.sample(count: 1001)

        #expect(samples.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(samples[400 ... 600].allSatisfy { $0 <= 0.9 + 1e-12 && $0 >= 0.2 - 1e-12 })
    }

    // MARK: - Sanitizing

    @Test func pointsAreSortedAndClamped() {
        let curves = ImageToneCurves(rgb: [Point(x: 1.2, y: 1), Point(x: 0.5, y: -0.4), Point(x: -1, y: 0)])

        #expect(curves.rgb == [Point(x: 0, y: 0), Point(x: 0.5, y: 0), Point(x: 1, y: 1)])
    }

    @Test func aPointTooCloseToTheOneBeforeIsDroppedButTheLastIsKept() {
        let curves = ImageToneCurves(rgb: [
            Point(x: 0, y: 0), Point(x: 0.005, y: 0.5), Point(x: 0.5, y: 0.5), Point(x: 0.995, y: 0.9), Point(x: 1, y: 1),
        ])

        #expect(curves.rgb == [Point(x: 0, y: 0), Point(x: 0.5, y: 0.5), Point(x: 1, y: 1)])
    }

    @Test func aPointExactlyTheGapFromItsNeighborIsKept() {
        let x = 0.37
        let curves = ImageToneCurves(rgb: [
            Point(x: 0, y: 0), Point(x: x, y: 0.3), Point(x: x + ImageToneCurves.minimumGap, y: 0.4), Point(x: 1, y: 1),
        ])

        #expect(curves.rgb.count == 4)
    }

    @Test func tooManyPointsKeepTheLast() {
        let points = (0 ... 30).map { Point(x: Double($0) / 30, y: Double($0) / 30) }
        let curves = ImageToneCurves(rgb: points)

        #expect(curves.rgb.count == ImageToneCurves.maximumPointCount)
        #expect(curves.rgb.last == Point(x: 1, y: 1))
    }

    @Test func fewerThanTwoPointsOrNonFiniteOnesGiveIdentity() {
        #expect(ImageToneCurves(rgb: [Point(x: 0.5, y: 0.5)]).isIdentity)
        #expect(ImageToneCurves(rgb: [Point(x: .nan, y: 0), Point(x: 0.4, y: .infinity)]).isIdentity)
    }

    @Test func assignmentSanitizesToo() {
        var curves = ImageToneCurves()
        curves[.green] = [Point(x: 0.8, y: 0.2), Point(x: 0.1, y: 0.9)]

        #expect(curves.green == [Point(x: 0.1, y: 0.9), Point(x: 0.8, y: 0.2)])
    }

    // MARK: - Coding

    @Test func curvesRoundTripThroughCodable() throws {
        let adjustments = ImageAdjustmentDescription(
            exposure: 0.5,
            curves: ImageToneCurves(blue: [Point(x: 0, y: 0.1), Point(x: 0.4, y: 0.6), Point(x: 1, y: 0.9)]),
            curvesBypassed: true
        )

        let data = try JSONEncoder().encode(adjustments)
        #expect(try JSONDecoder().decode(ImageAdjustmentDescription.self, from: data) == adjustments)
    }

    @Test func dataWrittenBeforeCurvesDecodesAsIdentity() throws {
        let decoded = try JSONDecoder().decode(ImageAdjustmentDescription.self, from: Data(#"{"exposure":1}"#.utf8))

        #expect(decoded.curves.isIdentity)
        #expect(!decoded.curvesBypassed)
    }

    @Test func storedPointsAreSanitizedOnDecode() throws {
        let json = #"{"rgb":[{"x":1,"y":1},{"x":0.3,"y":2},{"x":0,"y":0}]}"#
        let decoded = try JSONDecoder().decode(ImageToneCurves.self, from: Data(json.utf8))

        #expect(decoded.rgb == [Point(x: 0, y: 0), Point(x: 0.3, y: 1), Point(x: 1, y: 1)])
        #expect(decoded.red == ImageToneCurves.identityPoints)
    }

    /// Two points at one x make a vertical step, not a division by zero.
    @Test func aRepeatedInputGivesFiniteValues() {
        let curve = MonotoneCubicInterpolation(x: [0, 0.5, 0.5, 1], y: [0, 0.2, 0.8, 1])

        let sampled = curve.sample(count: 64)
        let values = [0.25, 0.5, 0.75].map { curve.value(at: $0) }

        #expect(sampled.allSatisfy { $0.isFinite })
        #expect(values.allSatisfy { $0.isFinite })
    }
}
