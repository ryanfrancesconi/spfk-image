// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import SPFKTesting
import Testing
import simd

@testable import SPFKImage

/// White balance: the Temperature/Tint solve, Auto White Balance's estimate, and the eyedropper's sample.
@Suite(.tags(.file))
final class ImageAdjustmentWhiteBalanceTests {
    typealias Parameter = ImageAdjustmentDescription.Parameter

    let context = CIContext()
    let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)

    private func flat(_ rgb: SIMD3<Double>, size: CGFloat = 1) throws -> CIImage {
        let space = try #require(linear)
        let color = try #require(CIColor(red: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1, colorSpace: space))
        return CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    /// Linear RGB of `image`'s pixel at its extent's origin.
    private func pixel(_ image: CIImage) throws -> SIMD3<Double> {
        var value = SIMD4<Float>.zero
        let space = try #require(linear)
        withUnsafeMutableBytes(of: &value) { buffer in
            guard let base = buffer.baseAddress else { return }
            context.render(
                image, toBitmap: base, rowBytes: 16,
                bounds: CGRect(origin: image.extent.origin, size: CGSize(width: 1, height: 1)),
                format: .RGBAf, colorSpace: space
            )
        }
        return SIMD3(Double(value.x), Double(value.y), Double(value.z))
    }

    private func color(_ rgb: SIMD3<Double>) throws -> CIColor {
        let space = try #require(linear)
        return try #require(CIColor(red: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1, colorSpace: space))
    }

    private func isGray(_ rgb: SIMD3<Double>, tolerance: Double = 0.005) -> Bool {
        abs(rgb.x / rgb.y - 1) < tolerance && abs(rgb.z / rgb.y - 1) < tolerance
    }

    static let casts: [(temperature: Double, tint: Double)] = [
        (0.05, -0.03), (0.3, 0), (-0.3, 0), (0, 0.3), (0.2, -0.4), (0.6, 0.4),
    ]

    @Test(arguments: casts)
    func solvedBalanceRendersTheCastColorGray(cast: (temperature: Double, tint: Double)) throws {
        let gray = try flat(SIMD3(0.2, 0.2, 0.2))
        let cast = try pixel(ImageAdjustmentRenderer.temperatureAndTint(gray, temperature: cast.temperature, tint: cast.tint))

        let balance = ImageAdjustmentRenderer.whiteBalance(neutralizing: try color(cast))
        let corrected = try pixel(
            ImageAdjustmentRenderer.temperatureAndTint(try flat(cast), temperature: balance.temperature, tint: balance.tint)
        )

        #expect(isGray(corrected), "\(cast) → \(balance) → \(corrected)")
    }

    @Test func solvedBalanceOpposesTheCast() throws {
        let gray = try flat(SIMD3(0.2, 0.2, 0.2))
        let warm = try pixel(ImageAdjustmentRenderer.temperatureAndTint(gray, temperature: 0.3, tint: 0.3))

        let balance = ImageAdjustmentRenderer.whiteBalance(neutralizing: try color(warm))

        #expect(balance.temperature < 0)
        #expect(balance.tint < 0)
    }

    @Test func grayNeedsNoBalance() throws {
        let balance = ImageAdjustmentRenderer.whiteBalance(neutralizing: try color(SIMD3(0.3, 0.3, 0.3)))

        #expect(abs(balance.temperature) < 0.005)
        #expect(abs(balance.tint) < 0.005)
    }

    @Test func colorBeyondReachStaysInRange() throws {
        let balance = ImageAdjustmentRenderer.whiteBalance(neutralizing: try color(SIMD3(0.05, 0.4, 0.05)))

        #expect(Parameter.temperature.range.contains(balance.temperature))
        #expect(Parameter.tint.range.contains(balance.tint))
        #expect(balance.temperature.isFinite && balance.tint.isFinite)
    }

    @Test func blackHasNoBalance() throws {
        let balance = ImageAdjustmentRenderer.whiteBalance(neutralizing: try color(SIMD3(0, 0, 0)))

        #expect(balance.temperature == 0 && balance.tint == 0)
    }

    // MARK: - Auto White Balance

    private func fixture() throws -> CIImage {
        let decoded = try #require(StillImageThumbnail.make(
            url: TestBundleResources.shared.sharksandwich,
            maxPixelSize: ImageAdjustmentRenderer.autoAnalysisSize,
            allowsEmbeddedThumbnail: false
        ))
        return CIImage(cgImage: decoded)
    }

    @Test func autoWhiteBalanceOpposesAnAddedCast() throws {
        let image = try fixture()
        let base = ImageAdjustmentRenderer.autoWhiteBalance(for: image)

        let warm = ImageAdjustmentRenderer.temperatureAndTint(image, temperature: 0.3, tint: 0.3).cropped(to: image.extent)
        let warmResult = ImageAdjustmentRenderer.autoWhiteBalance(for: warm)
        #expect(warmResult.color.temperature < base.color.temperature - 0.02, "\(base.color.temperature) → \(warmResult.color.temperature)")
        #expect(warmResult.color.tint < base.color.tint - 0.02, "\(base.color.tint) → \(warmResult.color.tint)")

        let cool = ImageAdjustmentRenderer.temperatureAndTint(image, temperature: -0.3, tint: -0.3).cropped(to: image.extent)
        let coolResult = ImageAdjustmentRenderer.autoWhiteBalance(for: cool)
        #expect(coolResult.color.temperature > base.color.temperature + 0.02, "\(base.color.temperature) → \(coolResult.color.temperature)")
        #expect(coolResult.color.tint > base.color.tint + 0.02, "\(base.color.tint) → \(coolResult.color.tint)")
        print("Auto white balance on sharksandwich: base \(base.color.temperature), \(base.color.tint); +0.3/+0.3 cast \(warmResult.color.temperature), \(warmResult.color.tint); −0.3/−0.3 cast \(coolResult.color.temperature), \(coolResult.color.tint)")
    }

    @Test func autoWhiteBalanceSetsOnlyTemperatureAndTint() throws {
        let auto = ImageAdjustmentRenderer.autoWhiteBalance(for: try fixture())

        #expect(Set(Parameter.allCases.filter { auto[$0] != 0 }).isSubset(of: Parameter.autoWhiteBalance))
        #expect(auto.curves == .identity)
    }

    @Test func saturatedImageHasNoNeutralEstimate() throws {
        let red = try flat(SIMD3(0.6, 0.1, 0.05), size: 64)

        #expect(ImageAdjustmentRenderer.neutralEstimate(of: red) == nil)
        #expect(ImageAdjustmentRenderer.autoWhiteBalance(for: red) == ImageAdjustmentDescription())
    }

    @Test func neutralEstimateIgnoresSaturatedAndClippedPixels() throws {
        let gray = try flat(SIMD3(0.3, 0.32, 0.28), size: 64)
        let red = try flat(SIMD3(0.7, 0.05, 0.05), size: 64).transformed(by: CGAffineTransform(translationX: 64, y: 0))
        let white = try flat(SIMD3(1, 1, 1), size: 64).transformed(by: CGAffineTransform(translationX: 128, y: 0))
        let image = white.composited(over: red.composited(over: gray))

        let estimate = try #require(ImageAdjustmentRenderer.neutralEstimate(of: image))

        #expect(abs(estimate.red - 0.3) < 0.01)
        #expect(abs(estimate.green - 0.32) < 0.01)
        #expect(abs(estimate.blue - 0.28) < 0.01)
    }

    @Test func applyingAutoWhiteBalanceReplacesOnlyTemperatureAndTint() {
        var current = ImageAdjustmentDescription()
        current.color.temperature = 0.4
        current.color.vibrance = 0.2
        var auto = ImageAdjustmentDescription()
        auto.color.temperature = -0.1
        auto.color.tint = 0.05
        auto.color.vibrance = 0.7

        let result = current.applyingAuto(auto, kind: .whiteBalance)

        #expect(result.color.temperature == -0.1)
        #expect(result.color.tint == 0.05)
        #expect(result.color.vibrance == 0.2)
    }

    // MARK: - Eyedropper

    /// Gray on the top half, a warm cast on the bottom; Core Image's origin is the bottom left.
    private func splitImage() throws -> CIImage {
        let warm = try pixel(ImageAdjustmentRenderer.temperatureAndTint(try flat(SIMD3(0.2, 0.2, 0.2)), temperature: 0.4, tint: 0))
        let bottom = try flat(warm, size: 40).cropped(to: CGRect(x: 0, y: 0, width: 40, height: 20))
        let top = try flat(SIMD3(0.2, 0.2, 0.2), size: 40).cropped(to: CGRect(x: 0, y: 20, width: 40, height: 20))
        return top.composited(over: bottom)
    }

    @Test func samplingMeasuresFromTheTopLeft() throws {
        let image = try splitImage()

        let top = try #require(ImageAdjustmentRenderer.whiteBalance(sampling: CGPoint(x: 0.5, y: 0.2), in: image))
        #expect(abs(top.temperature) < 0.005 && abs(top.tint) < 0.005)

        let bottom = try #require(ImageAdjustmentRenderer.whiteBalance(sampling: CGPoint(x: 0.5, y: 0.8), in: image))
        #expect(bottom.temperature < -0.1)
    }

    @Test func samplingOutsideTheImageIsNil() throws {
        let image = try splitImage()

        #expect(ImageAdjustmentRenderer.whiteBalance(sampling: CGPoint(x: 1.2, y: 0.5), in: image) == nil)
        #expect(ImageAdjustmentRenderer.whiteBalance(sampling: CGPoint(x: 0.5, y: -0.1), in: image) == nil)
    }

    @Test func everyTemperatureAndTintScalesAGrayWithoutDiverging() throws {
        let gray = try flat(SIMD3(repeating: 0.2))
        var diverging: [String] = []

        for temperature in stride(from: -1.0, through: 1.0, by: 0.1) {
            for tint in stride(from: -1.0, through: 1.0, by: 0.1) {
                let rendered = try pixel(ImageAdjustmentRenderer.temperatureAndTint(gray, temperature: temperature, tint: tint))
                let gains = rendered / 0.2
                if gains.min() <= 0.2 || gains.max() > 8 {
                    diverging.append(String(format: "%.1f, %.1f", temperature, tint))
                }
            }
        }

        #expect(diverging.isEmpty)
    }

    // MARK: - The matrix

    @Test func neutralIsExactlyIdentity() {
        #expect(ImageAdjustmentRenderer.whiteBalanceMatrix(temperature: 0, tint: 0) == matrix_identity_double3x3)
    }

    /// Linear gains on a gray, computed once from the shipped constants.
    static let grayGains: [(temperature: Double, tint: Double, gains: SIMD3<Double>)] = [
        (-1, 0, SIMD3(0.6958, 1.0252, 1.6457)),
        (1, 0, SIMD3(1.2336, 0.9706, 0.6036)),
        (0, -1, SIMD3(0.3581, 1.2297, 0.6147)),
        (0, 1, SIMD3(1.5704, 0.7481, 1.8158)),
        (-1, 1, SIMD3(0.5378, 0.4501, 7.8082)),
    ]

    @Test(arguments: grayGains)
    func aGrayTakesThePinnedGains(pin: (temperature: Double, tint: Double, gains: SIMD3<Double>)) throws {
        let computed = ImageAdjustmentRenderer.whiteBalanceMatrix(temperature: pin.temperature, tint: pin.tint) * SIMD3(repeating: 1)
        #expect(abs(computed - pin.gains).max() < 1e-4, "\(pin.temperature), \(pin.tint): \(computed)")

        let rendered = try pixel(ImageAdjustmentRenderer.temperatureAndTint(try flat(SIMD3(repeating: 0.2)), temperature: pin.temperature, tint: pin.tint))
        #expect(abs(rendered / 0.2 - pin.gains).max() < 0.01, "\(pin.temperature), \(pin.tint): rendered \(rendered / 0.2)")
    }

    @Test func aGrayKeepsItsLuminanceEverywhere() throws {
        let gray = try flat(SIMD3(repeating: 0.2))

        for temperature in stride(from: -1.0, through: 1.0, by: 0.5) {
            for tint in stride(from: -1.0, through: 1.0, by: 0.5) {
                let rendered = try pixel(ImageAdjustmentRenderer.temperatureAndTint(gray, temperature: temperature, tint: tint))
                let luminance = (rendered * ColorMath.luminanceWeights).sum()
                #expect(abs(luminance / 0.2 - 1) < 0.003, "\(temperature), \(tint): \(luminance / 0.2)")
            }
        }
    }

    /// ColorSync converts to its D50 connection space with a Bradford adaptation (ICC.1:2010 Annex E.3),
    /// so its linear sRGB to XYZ is the IEC matrix adapted from the IEC white with ours.
    @Test func bradfordAndTheSRGBMatrixMatchColorSync() throws {
        let source = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let xyz = try #require(CGColorSpace(name: CGColorSpace.genericXYZ))

        func converted(_ rgb: [CGFloat]) throws -> SIMD3<Double> {
            let color = try #require(CGColor(colorSpace: source, components: rgb + [1])?.converted(to: xyz, intent: .relativeColorimetric, options: nil))
            let values = try #require(color.components)
            return SIMD3(Double(values[0]), Double(values[1]), Double(values[2]))
        }

        let colorSync = simd_double3x3(columns: (try converted([1, 0, 0]), try converted([0, 1, 0]), try converted([0, 0, 1])))
        let bradford = ImageAdjustmentRenderer.bradford
        let sRGB = ImageAdjustmentRenderer.linearSRGBToXYZ
        let ratio = (bradford * colorSync * SIMD3(repeating: 1)) / (bradford * sRGB * SIMD3(repeating: 1))
        let predicted = bradford.inverse * simd_double3x3(diagonal: ratio) * bradford * sRGB

        for column in 0 ..< 3 {
            #expect(abs(predicted[column] - colorSync[column]).max() < 1e-4, "column \(column): \(predicted[column]) vs \(colorSync[column])")
        }
    }

    // MARK: - Slider tracks

    @Test func theTemperatureTrackRunsFromBlueThroughGrayToAmber() throws {
        let track = ImageAdjustmentRenderer.whiteBalanceTrack(component: .temperature, temperature: 0, tint: 0)
        let first = try #require(track.first)
        let last = try #require(track.last)
        let middle = track[track.count / 2]

        #expect(first.z - first.x > 0.1)
        #expect(last.z - last.x < -0.05)
        let gray = SIMD3<Double>(repeating: 0.5)
        let error = (middle - gray).replacing(with: gray - middle, where: middle .< gray).max()
        #expect(error < 1.0 / 255)
    }

    @Test func theTintTrackRunsFromGreenToMagenta() throws {
        let track = ImageAdjustmentRenderer.whiteBalanceTrack(component: .tint, temperature: 0, tint: 0)
        let first = try #require(track.first)
        let last = try #require(track.last)

        #expect((first.x + first.z) / 2 - first.y < -0.05)
        #expect((last.x + last.z) / 2 - last.y > 0.05)
    }

    @Test func theTemperatureTrackShowsTheCurrentTint() {
        let track = ImageAdjustmentRenderer.whiteBalanceTrack(component: .temperature, temperature: 0, tint: 1)
        let middle = track[track.count / 2]

        #expect((middle.x + middle.z) / 2 - middle.y > 0.05)
    }

    @Test(arguments: ImageAdjustmentRenderer.WhiteBalanceComponent.allCases)
    func aTrackMatchesTheRenderedStep(component: ImageAdjustmentRenderer.WhiteBalanceComponent) throws {
        let track = ImageAdjustmentRenderer.whiteBalanceTrack(component: component, temperature: -0.4, tint: 0.3, stops: 9)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let gray = CIImage(color: try #require(CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1, colorSpace: space)))
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))

        for (stop, color) in track.enumerated() {
            let value = -1 + 2 * Double(stop) / 8
            let rendered = ImageAdjustmentRenderer.temperatureAndTint(
                gray,
                temperature: component == .temperature ? value : -0.4,
                tint: component == .tint ? value : 0.3
            )
            var encoded = SIMD4<Float>.zero
            withUnsafeMutableBytes(of: &encoded) { buffer in
                guard let base = buffer.baseAddress else { return }
                context.render(rendered, toBitmap: base, rowBytes: 16, bounds: rendered.extent, format: .RGBAf, colorSpace: space)
            }
            let shown = SIMD3(Double(encoded.x), Double(encoded.y), Double(encoded.z)).clamped(lowerBound: .zero, upperBound: .one)
            #expect(abs(shown - color).max() < 2.0 / 255, "\(component) \(value): rendered \(shown), track \(color)")
        }
    }

    @Test func aTrackIsClampedToWhatADisplayShows() {
        let track = ImageAdjustmentRenderer.whiteBalanceTrack(component: .temperature, temperature: 0, tint: 1)

        #expect(track.allSatisfy { $0.min() >= 0 && $0.max() <= 1 })
    }
}
