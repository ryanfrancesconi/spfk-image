// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import SPFKTesting
import Testing

@testable import SPFKImage

/// Auto: Core Image's enhancement, mapped onto our fields, against Apple's own filters.
@Suite(.tags(.file))
final class ImageAdjustmentAutoTests {
    typealias Parameter = ImageAdjustmentDescription.Parameter

    let context = CIContext()

    static let fixtures = [
        TestBundleResources.shared.sharksandwich,
        TestBundleResources.shared.songbird,
        TestBundleResources.shared.sharksandwich_heic,
    ]

    private func analysisImage(_ url: URL) throws -> CIImage {
        let decoded = try #require(
            StillImageThumbnail.make(url: url, maxPixelSize: ImageAdjustmentRenderer.autoAnalysisSize, allowsEmbeddedThumbnail: false)
        )
        return CIImage(cgImage: decoded)
    }

    /// sRGB-encoded RGB of `image`, clamped to 0…1.
    private func pixels(_ image: CIImage) throws -> [Float] {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let rendered = try #require(context.createCGImage(image, from: image.extent, format: .RGBAf, colorSpace: space, deferred: false))
        let data = try #require(rendered.dataProvider?.data) as Data

        return data.withUnsafeBytes { buffer in
            (0 ..< rendered.height).flatMap { row -> [Float] in
                let start = buffer.baseAddress?.advanced(by: row * rendered.bytesPerRow).assumingMemoryBound(to: Float.self)
                let values = UnsafeBufferPointer(start: start, count: rendered.width * 4)
                return values.enumerated().filter { $0.offset % 4 != 3 }.map { min(max($0.element, 0), 1) }
            }
        }
    }

    private func psnr(_ a: [Float], _ b: [Float]) -> Double {
        let squaredError = zip(a, b).reduce(0.0) { $0 + Double(($1.0 - $1.1) * ($1.0 - $1.1)) }
        guard squaredError > 0 else { return .infinity }
        return 10 * log10(Double(a.count) / squaredError)
    }

    /// `image` white balanced by `balance`, then through Apple's own enhancement filters for the
    /// balanced image.
    private func appleReference(_ image: CIImage, balance: ImageAdjustmentDescription) throws -> CIImage {
        let balanced = ImageAdjustmentRenderer.temperatureAndTint(image, temperature: balance.color.temperature, tint: balance.color.tint)
            .cropped(to: image.extent)

        var apple = balanced
        for filter in balanced.autoAdjustmentFilters(options: [.redEye: false]) {
            filter.setValue(apple, forKey: kCIInputImageKey)
            apple = try #require(filter.outputImage)
        }
        return apple.cropped(to: image.extent)
    }

    @Test(arguments: fixtures)
    func autoRendersCloseToCoreImagesFilters(url: URL) throws {
        let image = try analysisImage(url)

        let auto = ImageAdjustmentRenderer.autoAdjustments(for: image)
        let apple = try appleReference(image, balance: auto)
        let ours = ImageAdjustmentRenderer.apply(auto, to: image)
        let measured = try psnr(pixels(apple), pixels(ours))

        print("Auto PSNR \(url.lastPathComponent): \(String(format: "%.1f", measured)) dB, temperature \(auto.color.temperature), tint \(auto.color.tint)")
        #expect(measured > 28, "\(url.lastPathComponent): \(measured) dB")
        #expect(!auto.isEmpty)
        #expect(Set(Parameter.allCases.filter { auto[$0] != 0 }).isSubset(of: Parameter.auto))
    }

    /// The enhancement analyzed on the unbalanced image, as Phase 9 first built it, against analyzing the
    /// balanced one; both measured against Apple's filters after the same white balance.
    @Test(arguments: fixtures)
    func analyzingTheBalancedImageIsNoWorse(url: URL) throws {
        let image = try analysisImage(url)
        let auto = ImageAdjustmentRenderer.autoAdjustments(for: image)
        let apple = try pixels(appleReference(image, balance: auto))

        var unbalanced = ImageAdjustmentRenderer.enhancement(for: image)
        unbalanced.color.temperature = auto.color.temperature
        unbalanced.color.tint = auto.color.tint

        let balancedPSNR = try psnr(apple, pixels(ImageAdjustmentRenderer.apply(auto, to: image)))
        let unbalancedPSNR = try psnr(apple, pixels(ImageAdjustmentRenderer.apply(unbalanced, to: image)))

        print("Auto analysis order \(url.lastPathComponent): balanced \(String(format: "%.1f", balancedPSNR)) dB, unbalanced \(String(format: "%.1f", unbalancedPSNR)) dB")
        #expect(balancedPSNR >= unbalancedPSNR - 1)
    }

    @Test func autoFromAFileMatchesItsAnalysisDecodeAndRepeats() throws {
        let url = TestBundleResources.shared.songbird
        let first = try #require(ImageAdjustmentRenderer.autoAdjustments(contentsOf: url))

        #expect(first == ImageAdjustmentRenderer.autoAdjustments(for: try analysisImage(url)))
        #expect(first == ImageAdjustmentRenderer.autoAdjustments(contentsOf: url))
    }

    @Test func inputPositionInvertsTheCurveBetweenItsPoints() {
        let points = [CGPoint(x: 0.02, y: 0), CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.4, y: 0.6), CGPoint(x: 0.7, y: 0.8), CGPoint(x: 0.96, y: 1)]

        #expect(ImageAdjustmentRenderer.inputPosition(of: 0, on: points) == 0.02)
        #expect(abs(ImageAdjustmentRenderer.inputPosition(of: 0.25, on: points) - 0.225) < 1e-9)
        #expect(abs(ImageAdjustmentRenderer.inputPosition(of: 0.5, on: points) - 0.35) < 1e-9)
        #expect(abs(ImageAdjustmentRenderer.inputPosition(of: 0.75, on: points) - 0.625) < 1e-9)
        #expect(abs(ImageAdjustmentRenderer.inputPosition(of: 1, on: points) - 0.96) < 1e-9)
    }

    @Test func identityCurveGivesNeutralLevels() {
        let identity = ImageAdjustmentDescription.Levels.identity.map { CGPoint(x: $0, y: $0) }
        var adjustments = ImageAdjustmentDescription()
        adjustments.levels.positions = ImageAdjustmentDescription.Levels.identity.map {
            ImageAdjustmentRenderer.inputPosition(of: $0, on: identity)
        }

        #expect(adjustments.levels.isNeutral)
    }

    @Test func applyingAutoReplacesOnlyTheFieldsAutoOwns() {
        let current = ImageAdjustmentDescription(
            light: .init(exposure: 0.5, shadows: -0.4),
            color: .init(vibrance: 0.9, sepia: 0.3),
            levels: .init(mid: 0.2),
            bypassed: [.light]
        )
        let auto = ImageAdjustmentDescription(
            light: .init(highlights: -0.1, shadows: 0.3),
            color: .init(vibrance: 0.05),
            levels: .init(black: 0.01)
        )

        let result = current.applyingAuto(auto)

        for parameter in Parameter.allCases {
            #expect(result[parameter] == (Parameter.auto.contains(parameter) ? auto : current)[parameter], "\(parameter)")
        }
        #expect(result.bypassed == current.bypassed)
        #expect(result.applyingAuto(auto) == result)
    }
}
