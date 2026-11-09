// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreGraphics
import CoreImage
import Foundation
import simd
@testable import SPFKImage
import Testing

@Suite("Selective Color")
struct ImageAdjustmentSelectiveColorTests {
    typealias Parameter = ImageAdjustmentDescription.Parameter
    typealias Band = ImageAdjustmentDescription.ColorBand

    // MARK: - Rendering helpers

    /// One pixel per color, 8-bit sRGB.
    private func strip(_ colors: [SIMD3<UInt8>]) throws -> CGImage {
        var bytes = [UInt8]()
        for color in colors {
            bytes += [color.x, color.y, color.z, 255]
        }

        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))

        return try #require(CGImage(
            width: colors.count, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: colors.count * 4,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    private func pixels(of image: CGImage) throws -> [SIMD3<Int>] {
        let width = image.width
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: 1))
        let data = try #require(context.data).bindMemory(to: UInt8.self, capacity: width * 4)

        return (0 ..< width).map { SIMD3(Int(data[$0 * 4]), Int(data[$0 * 4 + 1]), Int(data[$0 * 4 + 2])) }
    }

    private func render(_ adjustments: ImageAdjustmentDescription, _ colors: [SIMD3<UInt8>]) throws -> [SIMD3<Int>] {
        let source = try strip(colors)
        let output = try #require(ImageAdjustmentRenderer().render(adjustments, source: source))
        return try pixels(of: output)
    }

    private func levels(_ color: SIMD3<UInt8>) -> SIMD3<Int> {
        SIMD3(Int(color.x), Int(color.y), Int(color.z))
    }

    private func difference(_ a: SIMD3<Int>, _ b: SIMD3<Int>) -> Int {
        max(abs(a.x - b.x), abs(a.y - b.y), abs(a.z - b.z))
    }

    private static let red = SIMD3<UInt8>(255, 0, 0)
    private static let blue = SIMD3<UInt8>(0, 0, 255)
    private static let grays: [SIMD3<UInt8>] = [0, 40, 128, 200, 255].map { SIMD3(repeating: $0) }

    private func everyShift(_ value: Double) -> ImageAdjustmentDescription {
        var adjustments = ImageAdjustmentDescription()
        for parameter in ImageAdjustmentDescription.Group.selectiveColor.parameters {
            adjustments[parameter] = value
        }
        return adjustments
    }

    // MARK: - Transform

    @Test func neutralShiftsBuildAnIdentityCube() {
        let shifts = [SIMD3<Double>](repeating: .zero, count: Band.allCases.count)
        let data = ImageAdjustmentRenderer.buildColorCube(dimension: 8) {
            ImageAdjustmentRenderer.selectiveColor($0, shifts: shifts)
        }
        let identity = ImageAdjustmentRenderer.buildColorCube(dimension: 8) { $0 }

        let cube = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let expected = identity.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let maximumError = zip(cube, expected).map { abs($0 - $1) }.max() ?? 0

        #expect(maximumError < 1e-6)
    }

    @Test(arguments: [-1.0, 1.0])
    func graysAreUnchangedByAnyShift(value: Double) {
        let shifts = [SIMD3<Double>](repeating: SIMD3(repeating: value), count: Band.allCases.count)

        for level in stride(from: 0.0, through: 1.0, by: 0.1) {
            let gray = SIMD3(repeating: level)
            #expect(ImageAdjustmentRenderer.selectiveColor(gray, shifts: shifts) == gray)
        }
    }

    @Test func hslRoundTrips() {
        for color in [SIMD3(0.9, 0.2, 0.1), SIMD3(0.1, 0.8, 0.3), SIMD3(0.3, 0.4, 0.95), SIMD3(0.6, 0.1, 0.6)] {
            let hsl = ImageAdjustmentRenderer.hsl(color)
            let back = ImageAdjustmentRenderer.rgb(hue: hsl.hue, saturation: hsl.saturation, lightness: hsl.lightness)
            #expect(simd_distance(color, back) < 1e-9)
        }
    }

    // MARK: - Render

    @Test func neutralIsSkippedAndRendersUnchanged() throws {
        let colors = [Self.red, Self.blue] + Self.grays
        let output = try render(ImageAdjustmentDescription(), colors)
        #expect(output == colors.map(levels))
    }

    @Test(arguments: [-1.0, 1.0])
    func renderedGraysAreUnchanged(value: Double) throws {
        let output = try render(everyShift(value), Self.grays)

        for (pixel, gray) in zip(output, Self.grays) {
            #expect(difference(pixel, levels(gray)) <= 1, "gray \(gray.x) became \(pixel)")
        }
    }

    @Test func redSaturationDownDesaturatesRedAndLeavesBlue() throws {
        var adjustments = ImageAdjustmentDescription()
        adjustments.selectiveColor.red.saturation = -1

        let output = try render(adjustments, [Self.red, Self.blue])
        let red = output[0]

        #expect(red.max() - red.min() <= 2, "red became \(red)")
        #expect(difference(output[1], levels(Self.blue)) <= 1, "blue became \(output[1])")
    }

    @Test func redHueUpTurnsRedTowardYellow() throws {
        var adjustments = ImageAdjustmentDescription()
        adjustments.selectiveColor.red.hue = 1

        let red = try render(adjustments, [Self.red])[0]

        #expect(red.x > 250)
        #expect(red.y > 100, "red became \(red)")
        #expect(red.z < 5)
    }

    @Test(arguments: [(1.0, true), (-1.0, false)])
    func blueLuminanceMovesBlueLightnessOnly(value: Double, brightens: Bool) throws {
        var adjustments = ImageAdjustmentDescription()
        adjustments.selectiveColor.blue.luminance = value

        let output = try render(adjustments, [Self.blue, Self.red])
        let before = ImageAdjustmentRenderer.hsl(SIMD3(0, 0, 1)).lightness
        let blue = SIMD3(Double(output[0].x), Double(output[0].y), Double(output[0].z)) / 255
        let after = ImageAdjustmentRenderer.hsl(blue).lightness

        #expect(brightens ? after > before + 0.1 : after < before - 0.1, "blue became \(output[0])")
        #expect(difference(output[1], levels(Self.red)) <= 1)
    }

    @Test func aBypassedBandRendersUnchangedAndKeepsItsValue() throws {
        var adjustments = ImageAdjustmentDescription()
        adjustments.selectiveColor.red.saturation = -1
        adjustments.bypassed = Set(ImageAdjustmentDescription.Group.selectiveColor.parameters)

        let output = try render(adjustments, [Self.red])

        #expect(output == [levels(Self.red)])
        #expect(adjustments.selectiveColor.red.saturation == -1)
    }

    /// The cube's trilinear lookup against the transform evaluated directly, on a 256-step ramp of each
    /// primary and of each secondary, in 8-bit levels.
    @Test func cubeLookupStaysCloseToTheTransform() throws {
        var adjustments = ImageAdjustmentDescription()
        for band in Band.allCases {
            adjustments[band.hue] = 1
            adjustments[band.saturation] = -0.5
            adjustments[band.luminance] = 0.5
        }

        let shifts = Band.allCases.map { band in
            SIMD3(adjustments[band.hue], adjustments[band.saturation], adjustments[band.luminance])
        }

        let directions: [SIMD3<Double>] = [
            SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(1, 1, 0), SIMD3(0, 1, 1), SIMD3(1, 0, 1),
        ]

        var maximumError = 0
        for direction in directions {
            let ramp = (0 ..< 256).map { level in SIMD3(UInt8(direction.x * Double(level)), UInt8(direction.y * Double(level)), UInt8(direction.z * Double(level))) }
            let output = try render(adjustments, ramp)

            for (pixel, input) in zip(output, ramp) {
                let color = SIMD3(Double(input.x), Double(input.y), Double(input.z)) / 255
                let expected = (ImageAdjustmentRenderer.selectiveColor(color, shifts: shifts) * 255).rounded(.toNearestOrEven)
                maximumError = max(maximumError, difference(pixel, SIMD3(Int(expected.x), Int(expected.y), Int(expected.z))))
            }
        }

        print("Selective color cube error, maximum over ramps: \(maximumError) levels")
        #expect(maximumError <= 6)
    }

    // MARK: - Cube cache

    @Test func theCubeCacheBuildsOncePerValues() {
        let step = "test-\(UUID().uuidString)"
        var builds = 0

        func data(_ values: [Double]) -> Data {
            ImageAdjustmentRenderer.colorCubeData(step: step, values: values) { rgb in
                builds += 1
                return rgb * values[0]
            }
        }

        let first = data([0.5])
        let afterFirst = builds
        let second = data([0.5])

        #expect(afterFirst > 0)
        #expect(builds == afterFirst)
        #expect(first == second)

        let third = data([0.25])

        #expect(builds == afterFirst * 2)
        #expect(third != first)
    }

    /// Concurrent builds for one step, as a preview render and a Save can run, each get the cube for
    /// their own values.
    @Test func concurrentBuildsGetTheirOwnCubes() async {
        let step = "test-\(UUID().uuidString)"
        let scales = (1 ... 16).map { Double($0) / 16 }

        let built = await withTaskGroup(of: (Double, Data).self) { group in
            for _ in 0 ..< 4 {
                for scale in scales {
                    group.addTask {
                        (scale, ImageAdjustmentRenderer.colorCubeData(step: step, values: [scale]) { $0 * scale })
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        for (scale, data) in built {
            #expect(data == ImageAdjustmentRenderer.buildColorCube(dimension: ImageAdjustmentRenderer.colorCubeDimension) { $0 * scale })
        }
    }

    // MARK: - Storage

    @Test func selectiveColorRoundTripsThroughCodable() throws {
        var adjustments = ImageAdjustmentDescription()
        adjustments.selectiveColor.green.hue = 0.3
        adjustments.selectiveColor.magenta.luminance = -0.7

        let data = try JSONEncoder().encode(adjustments)
        let decoded = try JSONDecoder().decode(ImageAdjustmentDescription.self, from: data)

        #expect(decoded == adjustments)
    }

    @Test func eachBandOwnsThreeDistinctParameters() {
        let parameters = Band.allCases.flatMap(\.parameters)
        #expect(Set(parameters).count == parameters.count)
        #expect(Set(parameters) == Set(ImageAdjustmentDescription.Group.selectiveColor.parameters))
    }
}
