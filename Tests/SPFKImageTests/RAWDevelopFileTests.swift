// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import ImageIO
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKImage

/// `RAWDevelop` against real RAW files, named by `SPFK_RAW_SAMPLES` (see `RAWSamples`).
@Suite(.tags(.file), .serialized, .enabled(if: RAWSamples.folder != nil))
final class RAWDevelopFileTests: BinTestCase {
    private let quarter = RAWDevelop.Options(scaleFactor: RAWMeasure.scaleFactor)

    private func sample(_ name: String) throws -> URL {
        try #require(RAWSamples.url(name), "\(name) is not in the samples folder")
    }

    private func exposure(_ stops: Double) -> ImageAdjustmentDescription {
        ImageAdjustmentDescription(light: .init(exposure: stops))
    }

    private func measure(_ url: URL, _ adjustments: ImageAdjustmentDescription = ImageAdjustmentDescription()) throws -> RAWMeasure {
        try RAWMeasure(RAWDevelop.develop(contentsOf: url, adjustments: adjustments, options: quarter).image)
    }

    // MARK: - isRAW

    @Test func theContentDecidesWhatIsRAW() throws {
        #expect(try RAWDevelop.isRAW(contentsOf: sample("DSCF4449.RAF")))
        #expect(try RAWDevelop.isRAW(contentsOf: sample("P1061136.dng")))

        let jpeg = TestBundleResources.shared.songbird
        #expect(!RAWDevelop.isRAW(contentsOf: jpeg))

        let disguised = bin.appendingPathComponent("songbird.dng")
        try FileManager.default.copyItem(at: jpeg, to: disguised)
        #expect(!RAWDevelop.isRAW(contentsOf: disguised))
        #expect(throws: RAWDevelopError.unreadable) { try RAWDevelop.develop(contentsOf: disguised) }
    }

    // MARK: - Exposure

    /// Exposure in the develop recovers what the default develop clips, which exposure after it cannot.
    @Test func exposureRecoversHighlights() throws {
        let url = try sample("DSCF3303.RAF")

        let defaultDevelop = try RAWDevelop.develop(contentsOf: url, options: quarter)
        let darker = try RAWDevelop.develop(contentsOf: url, adjustments: exposure(-1.5), options: quarter)
        let afterDevelop = ImageAdjustmentRenderer.apply(exposure(-1.5), to: defaultDevelop.image)

        let defaultMeasure = try RAWMeasure(defaultDevelop.image)
        let darkerMeasure = try RAWMeasure(darker.image)
        let afterMeasure = try RAWMeasure(afterDevelop)

        print("DSCF3303 clipped at quarter scale: default \(defaultMeasure.clippedFraction), -1.5 EV \(darkerMeasure.clippedFraction)")

        #expect(darkerMeasure.clippedFraction > 0)
        #expect(darkerMeasure.clippedFraction < defaultMeasure.clippedFraction / 2)
        #expect(darker.remaining.light.exposure == 0)
        #expect(try #require(darkerMeasure.largestDifference(from: afterMeasure)) > 0.3)
    }

    @Test func aNeutralDevelopIsTheDefaultDevelop() throws {
        let url = try sample("01195_LCN Image.DNG")

        let developed = try RAWDevelop.develop(contentsOf: url)
        let bare = try #require(CIRAWFilter(imageURL: url)?.outputImage)

        #expect(developed.remaining.isEmpty)
        #expect(try #require(RAWMeasure(developed.image).largestDifference(from: RAWMeasure(bare))) == 0)
    }

    // MARK: - Orientation

    @Test func theOutputIsUprightUnlessAskedForStoredPixels() throws {
        let url = try sample("P1061136.dng")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), nil) as? [String: Any])
        let width = try #require(properties[kCGImagePropertyPixelWidth as String] as? Int)
        let height = try #require(properties[kCGImagePropertyPixelHeight as String] as? Int)
        let orientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1

        let displayed = ImageFormatConverter.displayedSize(width: width, height: height, orientation: orientation)

        let upright = try RAWDevelop.develop(contentsOf: url).image.extent
        #expect(Int(upright.width) == displayed.width)
        #expect(Int(upright.height) == displayed.height)

        let stored = try RAWDevelop.develop(contentsOf: url, options: .init(appliesFileOrientation: false)).image.extent
        #expect(Int(stored.width) == width)
        #expect(Int(stored.height) == height)
    }

    // MARK: - Decoder version

    @Test func aDecoderVersionChangesTheDevelop() throws {
        let url = try sample("01195_LCN Image.DNG")
        let versions = try #require(RAWDevelop.decoderVersions(contentsOf: url))

        #expect(versions.supported.count > 1)
        #expect(versions.supported.contains(versions.current))

        let first = try #require(versions.supported.first)
        try #require(first != versions.current)

        // The as-shot white under each version, read after the version is set.
        for version in [first, versions.current] {
            let filter = try #require(CIRAWFilter(imageURL: url))
            filter.decoderVersion = CIRAWDecoderVersion(rawValue: version)
            print("01195 decoder \(version): as-shot \(filter.neutralTemperature) K, tint \(filter.neutralTint)")
        }

        let pinned = try RAWMeasure(RAWDevelop.develop(contentsOf: url, decoderVersion: first, options: quarter).image)
        let current = try measure(url)

        print("01195 mean luminance: \(first) \(pinned.meanLuminance), \(versions.current) \(current.meanLuminance)")
        #expect(abs(pinned.meanLuminance - current.meanLuminance) > 0.01)

        #expect(throws: RAWDevelopError.unsupportedDecoderVersion("not-a-version")) {
            try RAWDevelop.develop(contentsOf: url, decoderVersion: "not-a-version")
        }
    }

    // MARK: - White balance and noise reduction

    @Test func temperatureAndTintReachTheFilter() throws {
        let url = try sample("DSCF4449.RAF")

        let neutral = try measure(url)
        let warmer = try measure(url, ImageAdjustmentDescription(color: .init(temperature: 0.5)))
        let cooler = try measure(url, ImageAdjustmentDescription(color: .init(temperature: -0.5)))
        let magenta = try measure(url, ImageAdjustmentDescription(color: .init(tint: 0.5)))

        func redOverBlue(_ m: RAWMeasure) -> Double { m.meanRed / m.meanBlue }
        func magentaOverGreen(_ m: RAWMeasure) -> Double { (m.meanRed + m.meanBlue) / m.meanGreen }

        #expect(redOverBlue(warmer) > redOverBlue(neutral))
        #expect(redOverBlue(cooler) < redOverBlue(neutral))
        #expect(magentaOverGreen(magenta) > magentaOverGreen(neutral))
    }

    @Test func noiseReductionReachesTheFilter() throws {
        let url = try sample("DSCF4449.RAF")
        let half = RAWDevelop.Options(scaleFactor: 0.5)

        let plain = try RAWDevelop.develop(contentsOf: url, options: half)
        let reduced = try RAWDevelop.develop(contentsOf: url, adjustments: ImageAdjustmentDescription(detail: .init(noiseReduction: 1)), options: half)

        #expect(reduced.remaining.detail.noiseReduction == 0)
        #expect(try #require(RAWMeasure(reduced.image).largestDifference(from: RAWMeasure(plain.image))) > 0)

        let plainNoise = try RAWMeasure.highFrequency(plain.image)
        let reducedNoise = try RAWMeasure.highFrequency(reduced.image)
        print("DSCF4449 high frequency at half scale: plain \(plainNoise), noise reduction 1 \(reducedNoise)")
        #expect(reducedNoise < plainNoise)
    }

    @Test func scaleFactorScalesTheOutput() throws {
        let url = try sample("DSCF4449.RAF")

        let full = try RAWDevelop.develop(contentsOf: url).image.extent
        let half = try RAWDevelop.develop(contentsOf: url, options: .init(scaleFactor: 0.5)).image.extent

        #expect(abs(half.width - full.width / 2) <= 1)
        #expect(abs(half.height - full.height / 2) <= 1)
    }

    @Test func aSessionCarriesNoSettingsOver() throws {
        let url = try sample("DSCF4449.RAF")
        let adjusted = ImageAdjustmentDescription(light: .init(exposure: -1.5), color: .init(temperature: 0.5))

        let session = try RAWDevelop.Session(contentsOf: url)
        _ = try RAWMeasure(session.develop(adjusted, options: quarter).image)
        let reused = try RAWMeasure(session.develop(ImageAdjustmentDescription(), options: quarter).image)

        let fresh = try RAWMeasure(RAWDevelop.Session(contentsOf: url).develop(ImageAdjustmentDescription(), options: quarter).image)

        // Assigning the as-shot white back, even unchanged, moves a channel by about 6e-7.
        #expect(try #require(reused.largestDifference(from: fresh)) < 1e-5)
    }
}
