// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import SPFKTesting
import Testing

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
        (0.05, -0.03), (0.3, 0), (-0.3, 0), (0, 0.3), (0.2, -0.4), (0.6, 0.6),
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
        #expect(warmResult.temperature < base.temperature - 0.02, "\(base.temperature) → \(warmResult.temperature)")
        #expect(warmResult.tint < base.tint - 0.02, "\(base.tint) → \(warmResult.tint)")

        let cool = ImageAdjustmentRenderer.temperatureAndTint(image, temperature: -0.3, tint: -0.3).cropped(to: image.extent)
        let coolResult = ImageAdjustmentRenderer.autoWhiteBalance(for: cool)
        #expect(coolResult.temperature > base.temperature + 0.02, "\(base.temperature) → \(coolResult.temperature)")
        #expect(coolResult.tint > base.tint + 0.02, "\(base.tint) → \(coolResult.tint)")
        print("Auto white balance on sharksandwich: base \(base.temperature), \(base.tint); +0.3/+0.3 cast \(warmResult.temperature), \(warmResult.tint); −0.3/−0.3 cast \(coolResult.temperature), \(coolResult.tint)")
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
        current.temperature = 0.4
        current.vibrance = 0.2
        var auto = ImageAdjustmentDescription()
        auto.temperature = -0.1
        auto.tint = 0.05
        auto.vibrance = 0.7

        let result = current.applyingAuto(auto, kind: .whiteBalance)

        #expect(result.temperature == -0.1)
        #expect(result.tint == 0.05)
        #expect(result.vibrance == 0.2)
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
}
