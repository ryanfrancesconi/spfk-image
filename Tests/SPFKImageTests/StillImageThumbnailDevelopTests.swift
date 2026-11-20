// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKImage

/// `StillImageThumbnail.developed` against real RAW files, named by `SPFK_RAW_SAMPLES` (see `RAWSamples`).
@Suite(.tags(.file, .rawDevelop), .serialized, .enabled(if: RAWSamples.folder != nil))
final class StillImageThumbnailDevelopTests: BinTestCase {
    private func sample(_ name: String) throws -> URL {
        try #require(RAWSamples.url(name), "\(name) is not in the samples folder")
    }

    private func recipe(_ adjustments: ImageAdjustmentDescription = ImageAdjustmentDescription(), decoderVersion: String? = nil) -> StillThumbnailRecipe {
        StillThumbnailRecipe(adjustments: adjustments, decoderVersion: decoderVersion, fingerprint: "test")
    }

    private func measure(_ image: CGImage) throws -> RAWMeasure {
        try RAWMeasure(CIImage(cgImage: image))
    }

    /// Mean of each pixel's largest channel minus its smallest.
    private func meanChroma(_ measure: RAWMeasure) -> Double {
        let count = measure.width * measure.height
        var sum = 0.0
        for i in 0 ..< count {
            let rgb = measure.pixels[i * 4 ..< i * 4 + 3]
            sum += Double((rgb.max() ?? 0) - (rgb.min() ?? 0))
        }
        return sum / Double(count)
    }

    @Test(arguments: ["DSCF4449.RAF", "P1061136.dng"])
    func theLongEdgeIsTheSizeAskedAndTheImageIsUpright(name: String) async throws {
        let url = try sample(name)

        let image = try await StillImageThumbnail.developed(url: url, maxPixelSize: 128, recipe: recipe())
        let decoded = try #require(StillImageThumbnail.make(url: url, maxPixelSize: 128, allowsEmbeddedThumbnail: false))

        #expect(abs(max(image.width, image.height) - 128) <= 1)

        let aspect = Double(image.width) / Double(image.height)
        let decodedAspect = Double(decoded.width) / Double(decoded.height)
        #expect(abs(aspect - decodedAspect) < 0.05, "developed \(image.width)x\(image.height), decoded \(decoded.width)x\(decoded.height)")
    }

    @Test func exposureInTheRecipeDarkensTheThumbnail() async throws {
        let url = try sample("DSCF4449.RAF")

        let plain = try await measure(StillImageThumbnail.developed(url: url, maxPixelSize: 128, recipe: recipe()))
        let darker = try await measure(StillImageThumbnail.developed(
            url: url, maxPixelSize: 128, recipe: recipe(ImageAdjustmentDescription(light: .init(exposure: -1)))
        ))

        print("DSCF4449 thumbnail mean luminance: plain \(plain.meanLuminance), -1 EV \(darker.meanLuminance)")

        #expect(darker.meanLuminance < plain.meanLuminance * 0.8)
    }

    /// Saturation is not taken by the develop, so it reaches the pixels through the renderer.
    @Test func aRemainingAdjustmentReachesThePixels() async throws {
        let url = try sample("DSCF4449.RAF")

        let plain = try await meanChroma(measure(StillImageThumbnail.developed(url: url, maxPixelSize: 128, recipe: recipe())))
        let desaturated = try await meanChroma(measure(StillImageThumbnail.developed(
            url: url, maxPixelSize: 128, recipe: recipe(ImageAdjustmentDescription(color: .init(saturation: -1)))
        )))

        print("DSCF4449 thumbnail mean chroma: plain \(plain), saturation -1 \(desaturated)")

        #expect(desaturated < plain * 0.2)
    }

    @Test func anUnsupportedDecoderVersionFallsBackToTheDefault() async throws {
        let url = try sample("DSCF4449.RAF")

        let image = try await StillImageThumbnail.developed(
            url: url, maxPixelSize: 128, recipe: recipe(decoderVersion: "not-a-version")
        )

        #expect(abs(max(image.width, image.height) - 128) <= 1)
    }

    @Test func aFileThatIsNotRAWThrows() async throws {
        await #expect(throws: RAWDevelopError.unreadable) {
            try await StillImageThumbnail.developed(url: TestBundleResources.shared.songbird, maxPixelSize: 128, recipe: self.recipe())
        }
    }
}
