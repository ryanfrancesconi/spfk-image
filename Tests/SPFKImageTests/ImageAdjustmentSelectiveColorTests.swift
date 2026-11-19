// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreGraphics
import CoreImage
import Foundation
import os
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
        let data = ColorCube.build(nodes: ColorCube.nodes(dimension: 8)) {
            SelectiveColorTransform(shifts: shifts)($0)
        }
        let identity = ColorCube.build(nodes: ColorCube.nodes(dimension: 8)) { $0.rgb }

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
            #expect(SelectiveColorTransform(shifts: shifts)(gray) == gray)
        }
    }

    private func oklch(_ rgb: SIMD3<Double>) -> (lightness: Double, chroma: Double, hue: Double) {
        let lab = ColorMath.oklab(rgb)
        return (lab.x, simd_length(SIMD2(lab.y, lab.z)), ColorMath.oklchHue(lab))
    }

    private func turn(_ a: Double, _ b: Double) -> Double {
        remainder(b - a, 360)
    }

    private func only(_ band: Band, _ shift: SIMD3<Double>) -> [SIMD3<Double>] {
        Band.allCases.map { $0 == band ? shift : .zero }
    }

    @Test(arguments: [(SIMD3(0.0, 1, 0), Band.green), (SIMD3(1.0, 0, 0), .red), (SIMD3(0.0, 0, 1), .blue)])
    func theCenterTurnsByTheFullReach(color: SIMD3<Double>, band: Band) {
        for direction in [-1.0, 1.0] {
            let turned = SelectiveColorTransform(shifts: only(band, SIMD3(direction, 0, 0)))(color)
            let degrees = turn(oklch(color).hue, oklch(turned).hue)

            #expect(abs(degrees - direction * ImageAdjustmentRenderer.maximumSelectiveHueShift) < 1, "\(band) \(direction): \(degrees)")
        }
    }

    /// A hue 20 degrees off green's center, as yellow-green foliage is, takes most of a green edit.
    @Test(arguments: [-20.0, 20])
    func aHueTwentyDegreesOffTheCenterTakesMostOfTheTurn(offset: Double) {
        let hue = HueBands.centers[2] + offset
        let color = ColorMath.sRGB(lightness: 0.6, chroma: 0.12, hue: hue)
        let turned = SelectiveColorTransform(shifts: only(.green, SIMD3(-1, 0, 0)))(color)
        let degrees = turn(oklch(color).hue, oklch(turned).hue)

        #expect(-degrees > 0.7 * ImageAdjustmentRenderer.maximumSelectiveHueShift, "\(degrees)")
    }

    @Test func theOppositeHueDoesNotMove() {
        let hue = HueBands.centers[2] + 180
        let color = ColorMath.sRGB(lightness: 0.6, chroma: 0.15, hue: hue)

        for shift in [SIMD3(1.0, 1, 1), SIMD3(-1.0, -1, -1)] {
            #expect(SelectiveColorTransform(shifts: only(.green, shift))(color) == color)
        }
    }

    @Test func neighboringBandsOverlap() {
        let yellow = HueBands.centers[1]
        let green = HueBands.centers[2]

        #expect(HueBands.weight(hue: yellow, center: green) > 0.3)
        #expect(HueBands.weight(hue: green, center: green) == 1)
        #expect(HueBands.weight(hue: green + HueBands.defaultWidth, center: green) == 0)
    }

    /// A green edit on a hue `offset` degrees above green's center, at `range`.
    private func greenTurn(offset: Double, range: Double) -> Double {
        let color = ColorMath.sRGB(lightness: 0.6, chroma: 0.1, hue: HueBands.centers[2] + offset)
        let widths = Band.allCases.map { HueBands.width(range: $0 == .green ? range : 0) }
        let turned = SelectiveColorTransform(shifts: only(.green, SIMD3(-1, 0, 0)), widths: widths)(color)
        return turn(oklch(color).hue, oklch(turned).hue)
    }

    @Test(arguments: [-1.0, 1.0])
    func rangeKeepsTheCentersTurn(range: Double) {
        let atZero = greenTurn(offset: 0, range: 0)
        #expect(atZero < -10)
        #expect(abs(greenTurn(offset: 0, range: range) - atZero) < 1e-9)
    }

    @Test func rangeWidensAndNarrowsTheBand() {
        #expect(greenTurn(offset: 100, range: 0) == 0)
        #expect(greenTurn(offset: 100, range: 1) < -5)
        #expect(abs(greenTurn(offset: 30, range: -1)) < 0.25 * abs(greenTurn(offset: 30, range: 0)))
        #expect(greenTurn(offset: 45, range: -1) == 0)
    }

    @Test func rangeAloneRendersUnchanged() throws {
        var adjustments = ImageAdjustmentDescription()
        for band in Band.allCases {
            adjustments[band.range] = 1
        }
        let colors = [Self.red, Self.blue, SIMD3(40, 200, 90)] + Self.grays

        #expect(try render(adjustments, colors) == colors.map(levels))
    }

    @Test(arguments: [-1.0, 1.0])
    func luminanceMovesADullColorLessThanAVividOne(value: Double) {
        let vivid = ColorMath.rgb(hue: 120, saturation: 1, lightness: 0.4)
        let dull = ColorMath.rgb(hue: 120, saturation: 0.25, lightness: 0.4)
        let shifts = only(.green, SIMD3(0, 0, value))

        let vividMove = abs(oklch(SelectiveColorTransform(shifts: shifts)(vivid)).lightness - oklch(vivid).lightness)
        let dullMove = abs(oklch(SelectiveColorTransform(shifts: shifts)(dull)).lightness - oklch(dull).lightness)

        #expect(dullMove > 0.01)
        #expect(dullMove < 0.5 * vividMove, "dull \(dullMove), vivid \(vividMove)")
    }

    /// Doubling the chroma of colors already at sRGB's edge keeps their hue: the excess is taken off
    /// chroma rather than clipped off a channel.
    @Test func saturationAtTheGamutEdgeKeepsHue() {
        let shifts = [SIMD3<Double>](repeating: SIMD3(0, 1, 0), count: Band.allCases.count)

        for hue in stride(from: 0.0, to: 360, by: 10) {
            for lightness in [0.3, 0.5, 0.7] {
                let color = ColorMath.rgb(hue: hue, saturation: 0.9, lightness: lightness)
                let output = SelectiveColorTransform(shifts: shifts)(color)

                #expect(output.min() >= 0 && output.max() <= 1)
                #expect(abs(turn(oklch(color).hue, oklch(output).hue)) < 1.5, "HSL \(hue) L \(lightness): \(output)")
                #expect(oklch(output).chroma >= oklch(color).chroma - 0.002, "HSL \(hue) L \(lightness) lost chroma")
            }
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

        #expect(red.x > 150, "red became \(red)")
        #expect(red.y > 100, "red became \(red)")
        #expect(red.z < 30, "red became \(red)")
    }

    @Test(arguments: [(1.0, true), (-1.0, false)])
    func blueLuminanceMovesBlueLightnessOnly(value: Double, brightens: Bool) throws {
        var adjustments = ImageAdjustmentDescription()
        adjustments.selectiveColor.blue.luminance = value

        let output = try render(adjustments, [Self.blue, Self.red])
        let before = oklch(SIMD3(0, 0, 1)).lightness
        let blue = SIMD3(Double(output[0].x), Double(output[0].y), Double(output[0].z)) / 255
        let after = oklch(blue).lightness

        #expect(brightens ? after > before + 0.08 : after < before - 0.2, "blue became \(output[0])")
        #expect(difference(output[1], levels(Self.red)) <= 1)
    }

    @Test func aBypassedBandRendersUnchangedAndKeepsItsValue() throws {
        var adjustments = ImageAdjustmentDescription()
        adjustments.selectiveColor.red.saturation = -1
        adjustments.bypassed = [.selectiveColor]

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
                let expected = (SelectiveColorTransform(shifts: shifts)(color) * 255).rounded(.toNearestOrEven)
                maximumError = max(maximumError, difference(pixel, SIMD3(Int(expected.x), Int(expected.y), Int(expected.z))))
            }
        }

        print("Selective color cube error, maximum over ramps: \(maximumError) levels")
        #expect(maximumError <= 7)
    }

    // MARK: - Cube cache

    /// Counts its evaluations, so a test sees whether its cube was rebuilt. Each cache test has its own
    /// type, since the cache holds one cube per type.
    private struct CountingScale: ColorCubeTransform {
        static let evaluations = OSAllocatedUnfairLock(initialState: 0)
        let scale: Double

        func callAsFunction(_ node: ColorCubeNode) -> SIMD3<Double> {
            Self.evaluations.withLock { $0 += 1 }
            return node.rgb * scale
        }
    }

    private struct Scale: ColorCubeTransform {
        let scale: Double

        func callAsFunction(_ node: ColorCubeNode) -> SIMD3<Double> {
            node.rgb * scale
        }
    }

    @Test func theCubeCacheBuildsOncePerValues() {
        var builds: Int { CountingScale.evaluations.withLock { $0 } }

        func data(_ values: [Double]) -> Data {
            ColorCube.data(for: CountingScale(scale: values[0]))
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
        let scales = (1 ... 16).map { Double($0) / 16 }

        let built = await withTaskGroup(of: (Double, Data).self) { group in
            for _ in 0 ..< 4 {
                for scale in scales {
                    group.addTask {
                        (scale, ColorCube.data(for: Scale(scale: scale)))
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        for (scale, data) in built {
            #expect(data == ColorCube.build(nodes: ColorCube.sRGBNodes) { $0.rgb * scale })
        }
    }

    // MARK: - Slider tracks

    private func isGray(_ rgb: SIMD3<Double>) -> Bool {
        rgb.max() - rgb.min() < 1e-6
    }

    @Test(arguments: Band.allCases)
    func theHueTrackSpansTheFullReachEitherSideOfTheReference(band: Band) {
        let track = ImageAdjustmentRenderer.selectiveColorTrack(band, component: .hue, shift: .init(), stops: 25)
        let reference = HueBands.reference(band)
        let reach = ImageAdjustmentRenderer.maximumSelectiveHueShift

        #expect(abs(turn(HueBands.center(band), oklch(reference).hue)) < 0.5, "\(band)")
        #expect(simd_distance(track[12], reference) < 1e-9)
        #expect(abs(turn(oklch(reference).hue, oklch(track[0]).hue) + reach) < 1, "\(band)")
        #expect(abs(turn(oklch(reference).hue, oklch(track[24]).hue) - reach) < 1, "\(band)")
    }

    /// Chroma rises from gray to the reference and never falls after it. Past the reference sRGB's
    /// edge can hold it still: cyan's reference is close to the most colorful cyan at its lightness.
    @Test(arguments: Band.allCases)
    func theSaturationTrackRisesFromGray(band: Band) {
        let track = ImageAdjustmentRenderer.selectiveColorTrack(band, component: .saturation, shift: .init(), stops: 25)
        let chroma = track.map { oklch($0).chroma }

        #expect(isGray(track[0]))
        for (lower, higher) in zip(chroma, chroma.dropFirst()) {
            #expect(higher > lower - 0.002, "\(band)")
        }
        #expect(chroma[12] > chroma[6] + 0.02, "\(band): \(chroma)")
    }

    @Test func theLuminanceTrackRisesThroughTheReference() {
        let track = ImageAdjustmentRenderer.selectiveColorTrack(.cyan, component: .luminance, shift: .init(), stops: 25)
        let lightness = track.map { oklch($0).lightness }
        let reference = HueBands.reference(.cyan)

        for (lower, higher) in zip(lightness, lightness.dropFirst()) {
            #expect(higher > lower)
        }
        #expect(simd_distance(track[12], reference) < 1e-9)
    }

    @Test func theHueTrackCarriesTheBandsOtherShifts() {
        let shift = ImageAdjustmentDescription.SelectiveColor.Shift(hue: 0.7, saturation: -1, luminance: 0.4)
        let track = ImageAdjustmentRenderer.selectiveColorTrack(.yellow, component: .hue, shift: shift, stops: 25)

        #expect(track.allSatisfy(isGray))
    }

    // MARK: - Storage

    @Test func selectiveColorRoundTripsThroughCodable() throws {
        var adjustments = ImageAdjustmentDescription()
        adjustments.selectiveColor.green.hue = 0.3
        adjustments.selectiveColor.magenta.luminance = -0.7
        adjustments.selectiveColor.blue.range = 0.4

        let data = try JSONEncoder().encode(adjustments)
        let decoded = try JSONDecoder().decode(ImageAdjustmentDescription.self, from: data)

        #expect(decoded == adjustments)
    }

    @Test func aShiftSavedWithoutRangeLoadsAtRangeZero() throws {
        let json = #"{"hue": 0.2, "saturation": -0.1, "luminance": 0.3}"#
        let decoded = try JSONDecoder().decode(ImageAdjustmentDescription.SelectiveColor.Shift.self, from: Data(json.utf8))

        #expect(decoded == .init(hue: 0.2, saturation: -0.1, luminance: 0.3, range: 0))
    }

    @Test func eachBandOwnsDistinctParameters() {
        let parameters = Band.allCases.flatMap(\.parameters)
        #expect(Set(parameters).count == parameters.count)
        #expect(Set(parameters) == Set(ImageAdjustmentDescription.Group.selectiveColor.parameters))
    }
}
