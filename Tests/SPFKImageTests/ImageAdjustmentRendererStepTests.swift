// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import SPFKTesting
import Testing

@testable import SPFKImage

/// Vibrance, vignette and its shape, and resolution-independent radii.
@Suite(.tags(.file))
final class ImageAdjustmentRendererStepTests {
    let context = CIContext()
    let source: CGImage
    let input: CIImage

    init() throws {
        source = try CGImage.contentsOf(url: TestBundleResources.shared.songbird)
        input = CIImage(cgImage: source)
    }

    private func pixels(_ adjustments: ImageAdjustmentDescription, sourceScale: Double = 1, of image: CIImage? = nil) throws -> [Float] {
        let image = image ?? input
        return try ImageAdjustmentChainPinTests.floatPixels(
            ImageAdjustmentRenderer.apply(adjustments, to: image, sourceScale: sourceScale), context: context
        )
    }

    private static func maximumDifference(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).map { abs($0 - $1) }.max() ?? 0
    }

    // MARK: - Skipped at neutral, active otherwise

    @Test(arguments: [ImageAdjustmentDescription.Parameter.vibrance, .blackPoint, .whitePoint, .brightness, .brilliance, .definition, .noiseReduction, .vignette])
    func aNewStepChangesTheOutputOnlyWhenNonZero(parameter: ImageAdjustmentDescription.Parameter) throws {
        var adjusted = ImageAdjustmentChainPinTests.pinned
        let base = try pixels(adjusted)

        adjusted[parameter] = 0.6
        #expect(Self.maximumDifference(base, try pixels(adjusted)) > 0.01)

        adjusted[parameter] = 0
        #expect(Self.maximumDifference(base, try pixels(adjusted)) == 0)
    }

    @Test func vibranceRaisesColorSpread() throws {
        let renderer = ImageAdjustmentRenderer()
        let stats = { (a: ImageAdjustmentDescription) throws -> ImageStatistics in
            let rendered = try #require(renderer.render(a, source: self.source))
            return try #require(ImageStatistics(rendered))
        }

        let neutral = try stats(.init())
        #expect(try stats(.init(color: .init(vibrance: 1))).meanChannelSpread > neutral.meanChannelSpread)
        #expect(try stats(.init(color: .init(vibrance: -1))).meanChannelSpread < neutral.meanChannelSpread)
    }

    // MARK: - Negative vibrance

    /// sRGB-encoded `colors` rendered through `adjustments` as a one-row image, read back sRGB-encoded.
    private func rendered(_ colors: [SIMD3<Double>], _ adjustments: ImageAdjustmentDescription) throws -> [SIMD3<Double>] {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let floats = colors.flatMap { color -> [Float] in [Float(color.x), Float(color.y), Float(color.z), 1] }
        let image = CIImage(
            bitmapData: floats.withUnsafeBufferPointer { Data(buffer: $0) },
            bytesPerRow: colors.count * 16,
            size: CGSize(width: colors.count, height: 1),
            format: .RGBAf,
            colorSpace: space
        )
        let linear = try pixels(adjustments, of: image)

        return colors.indices.map { index in
            let pixel = linear[index * 4 ..< index * 4 + 3].map { ImageAdjustmentRenderer.sRGBEncoded(Double($0)) }
            return SIMD3(pixel[0], pixel[1], pixel[2])
        }
    }

    private static func oklchChroma(_ rgb: SIMD3<Double>) -> Double {
        let lab = ImageAdjustmentRenderer.oklab(rgb)
        return (lab.y * lab.y + lab.z * lab.z).squareRoot()
    }

    /// One HSL hue sweep per (saturation, lightness), a degree apart.
    private static let hueSweeps: [[SIMD3<Double>]] = [(1, 0.5), (0.8, 0.5), (0.5, 0.5), (0.8, 0.3), (0.8, 0.7)].map { saturation, lightness in
        (0 ... 360).map { ImageAdjustmentRenderer.rgb(hue: Double($0), saturation: saturation, lightness: lightness) }
    }

    /// `CIVibrance` at −1 changes a channel by up to 0.06 between neighboring degrees of these sweeps.
    @Test func negativeVibranceMutesWithoutAStepAcrossHues() throws {
        for sweep in Self.hueSweeps {
            let output = try rendered(sweep, .init(color: .init(vibrance: -1)))
            let largestStep = zip(output, output.dropFirst()).map { previous, next in
                let step = next - previous
                return max(step.max(), -step.min())
            }.max() ?? 0
            #expect(largestStep < 0.035)
        }
    }

    @Test func negativeVibranceHoldsLightnessAndHue() throws {
        for sweep in Self.hueSweeps {
            let output = try rendered(sweep, .init(color: .init(vibrance: -1)))

            for (input, muted) in zip(sweep, output) {
                let before = ImageAdjustmentRenderer.oklab(input)
                let after = ImageAdjustmentRenderer.oklab(muted)
                #expect(abs(after.x - before.x) < 0.01)
                #expect(Self.oklchChroma(muted) < Self.oklchChroma(input))
            }
        }
    }

    @Test func negativeVibranceSparesSkinMoreThanBlue() throws {
        let skin = SIMD3<Double>(198, 120, 86) / 255
        let blue = SIMD3<Double>(70, 110, 200) / 255
        let output = try rendered([skin, blue], .init(color: .init(vibrance: -1)))

        let skinKept = Self.oklchChroma(output[0]) / Self.oklchChroma(skin)
        let blueKept = Self.oklchChroma(output[1]) / Self.oklchChroma(blue)
        #expect(skinKept > 0.6)
        #expect(blueKept < 0.2)
    }

    @Test func negativeVibranceChangesTheOutputOnlyWhenNonZero() throws {
        var adjusted = ImageAdjustmentChainPinTests.pinned
        let base = try pixels(adjusted)

        adjusted.color.vibrance = -0.6
        #expect(Self.maximumDifference(base, try pixels(adjusted)) > 0.01)

        adjusted.color.vibrance = 0
        #expect(Self.maximumDifference(base, try pixels(adjusted)) == 0)
    }

    @Test func positiveVibranceIsCoreImagesFilter() throws {
        let filter = CIFilter.vibrance()
        filter.inputImage = input
        filter.amount = 0.6
        let reference = try ImageAdjustmentChainPinTests.floatPixels(try #require(filter.outputImage).cropped(to: input.extent), context: context)

        #expect(Self.maximumDifference(reference, try pixels(.init(color: .init(vibrance: 0.6)))) == 0)
    }

    // MARK: - Vignette

    /// Mean linear luminance of a corner patch and of the center patch.
    private func cornerAndCenter(_ adjustments: ImageAdjustmentDescription) throws -> (corner: Double, center: Double) {
        let p = try pixels(adjustments)
        let width = Int(input.extent.width), height = Int(input.extent.height)
        let patch = max(4, min(width, height) / 20)

        func mean(x0: Int, y0: Int) -> Double {
            var sum = 0.0
            for y in y0 ..< y0 + patch {
                for x in x0 ..< x0 + patch {
                    let i = (y * width + x) * 4
                    sum += Double(0.2126 * p[i] + 0.7152 * p[i + 1] + 0.0722 * p[i + 2])
                }
            }
            return sum / Double(patch * patch)
        }

        return (mean(x0: 0, y0: 0), mean(x0: width / 2 - patch / 2, y0: height / 2 - patch / 2))
    }

    @Test func positiveVignetteDarkensTheCornersAndKeepsTheCenter() throws {
        let neutral = try cornerAndCenter(.init())
        let vignetted = try cornerAndCenter(.init(vignette: .init(amount: 1)))

        #expect(vignetted.corner < neutral.corner * 0.8)
        #expect(abs(vignetted.center - neutral.center) < neutral.center * 0.01)
    }

    @Test func negativeVignetteLightensTheCorners() throws {
        let neutral = try cornerAndCenter(.init())
        let lightened = try cornerAndCenter(.init(vignette: .init(amount: -1)))

        #expect(lightened.corner > neutral.corner * 1.2)
        #expect(abs(lightened.center - neutral.center) < neutral.center * 0.01)
    }

    @Test func aWiderRadiusLeavesTheCornersBrighter() throws {
        let neutral = try cornerAndCenter(.init(vignette: .init(amount: 1)))
        let wide = try cornerAndCenter(.init(vignette: .init(amount: 1, radius: 1)))
        let narrow = try cornerAndCenter(.init(vignette: .init(amount: 1, radius: -1)))

        #expect(wide.corner > neutral.corner)
        #expect(narrow.corner < neutral.corner)
    }

    @Test(arguments: [ImageAdjustmentDescription.Parameter.vignetteRadius, .vignetteSoftness])
    func vignetteShapeActsOnlyWithAVignette(parameter: ImageAdjustmentDescription.Parameter) throws {
        var adjusted = ImageAdjustmentChainPinTests.pinned
        let base = try pixels(adjusted)
        adjusted[parameter] = 0.6
        #expect(Self.maximumDifference(base, try pixels(adjusted)) == 0)

        adjusted.vignette.amount = 0.8
        let vignetted = try pixels(adjusted)
        adjusted[parameter] = 0
        #expect(Self.maximumDifference(vignetted, try pixels(adjusted)) > 0.01)
    }

    // MARK: - Sharpness radius

    @Test func sharpnessRadiusActsOnlyWithSharpness() throws {
        var adjusted = ImageAdjustmentChainPinTests.pinned
        adjusted.detail.sharpness = 0
        let base = try pixels(adjusted)
        adjusted.detail.sharpnessRadius = 0.6
        #expect(Self.maximumDifference(base, try pixels(adjusted)) == 0)

        adjusted.detail.sharpness = 0.6
        let sharpened = try pixels(adjusted)
        adjusted.detail.sharpnessRadius = 0
        #expect(Self.maximumDifference(sharpened, try pixels(adjusted)) > 0.01)
    }

    @Test func aWiderSharpnessRadiusChangesMoreOfTheImage() throws {
        let plain = try pixels(.init())
        let changed = { (radius: Double) throws -> Double in
            let sharpened = try self.pixels(.init(detail: .init(sharpness: 1, sharpnessRadius: radius)))
            return zip(plain, sharpened).map { Double(abs($0 - $1)) }.reduce(0, +)
        }

        let narrow = try changed(-1)
        let neutral = try changed(0)
        let wide = try changed(1)
        #expect(narrow < neutral)
        #expect(neutral < wide)
    }

    // MARK: - Source scale

    @Test func sourceScaleComparesTheLongerSides() {
        let upright = CGRect(x: 0, y: 0, width: 750, height: 1000)

        #expect(ImageAdjustmentRenderer.sourceScale(of: upright, fullWidth: 4000, fullHeight: 3000) == 0.25)
        #expect(ImageAdjustmentRenderer.sourceScale(of: upright, fullWidth: 3000, fullHeight: 4000) == 0.25)
        #expect(ImageAdjustmentRenderer.sourceScale(of: upright, fullWidth: nil, fullHeight: 4000) == 1)
        #expect(ImageAdjustmentRenderer.sourceScale(of: upright, fullWidth: 0, fullHeight: 0) == 1)
    }

    /// A quarter-size render with its radii scaled resembles the full render downsampled, closer than
    /// the same render with full-size radii.
    @Test func aDownsampledRenderMatchesTheFullRenderWhenScaled() throws {
        let adjustments = ImageAdjustmentDescription(detail: .init(sharpness: 1))

        let full = try ImageAdjustmentChainPinTests.floatPixels(
            Self.quarter(ImageAdjustmentRenderer.apply(adjustments, to: input)), context: context
        )
        let small = Self.quarter(input)
        let scaled = try pixels(adjustments, sourceScale: 0.25, of: small)
        let unscaled = try pixels(adjustments, sourceScale: 1, of: small)

        let withScale = Self.psnr(full, scaled)
        let withoutScale = Self.psnr(full, unscaled)
        print("sourceScale PSNR, quarter size, sharpness 1: with \(withScale) dB, without \(withoutScale) dB")

        #expect(withScale > withoutScale + 1)
    }

    private static func quarter(_ image: CIImage) -> CIImage {
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = 0.25
        filter.aspectRatio = 1
        let output = filter.outputImage ?? image
        let extent = output.extent
        return output.cropped(to: CGRect(x: 0, y: 0, width: extent.width.rounded(.down), height: extent.height.rounded(.down)))
    }

    /// Over RGB, with values clamped to 0…1.
    private static func psnr(_ a: [Float], _ b: [Float]) -> Double {
        var sum = 0.0, count = 0
        for i in stride(from: 0, to: min(a.count, b.count), by: 4) {
            for c in 0 ..< 3 {
                let d = Double(min(max(a[i + c], 0), 1) - min(max(b[i + c], 0), 1))
                sum += d * d
                count += 1
            }
        }
        let mse = sum / Double(max(count, 1))
        return mse == 0 ? .infinity : 10 * log10(1 / mse)
    }
}
