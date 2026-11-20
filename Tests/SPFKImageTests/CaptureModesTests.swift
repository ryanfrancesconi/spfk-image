// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import ImageIO
import SPFKBase
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

@Suite(.tags(.file, .captureModes))
final class CaptureModesTests: BinTestCase {
    @Test(arguments: [UTType.jpeg, .heic], AdjustmentFileFixtures.GainMapFormat.allCases)
    func aGainMapReadsAsHDR(type: UTType, format: AdjustmentFileFixtures.GainMapFormat) async throws {
        guard #available(macOS 15, iOS 18, *) else { return }

        let url = try await AdjustmentFileFixtures.gainMapped(type, format: format, in: bin)
        let modes = try CaptureModesOracle.read(url)
        let decoded = try await CaptureModesOracle.decoded(url)

        #expect(decoded.contains(.hdr))
        #expect(modes == decoded)
    }

    @Test func aPlainJPEGHasNoModes() throws {
        #expect(try CaptureModesOracle.read(TestBundleResources.shared.songbird) == [])
    }

    @Test func makerAppleTag17MarksALivePhoto() {
        let live: [CFString: Any] = [kCGImagePropertyMakerAppleDictionary: ["17": "6A1E0C7B-0000"]]
        let empty: [CFString: Any] = [kCGImagePropertyMakerAppleDictionary: ["17": ""]]
        let other: [CFString: Any] = [kCGImagePropertyMakerAppleDictionary: ["11": "burst"]]

        #expect(CaptureModes.isLivePhoto(live))
        #expect(!CaptureModes.isLivePhoto(empty))
        #expect(!CaptureModes.isLivePhoto(other))
        #expect(!CaptureModes.isLivePhoto([:]))
    }
}

/// `CaptureModes` against every image in the sample folders, with each expectation read from the file
/// by decoding its maps.
@Suite(.tags(.file, .captureModes), .serialized)
struct CaptureModesSampleTests {
    @Test(.enabled(if: RAWSamples.folder != nil))
    func theRAWSamplesMatchTheirDecodedMaps() async throws {
        try await check(try #require(RAWSamples.folder))
    }

    @Test(.tags(.slow), .enabled(if: CaptureSamples.folder != nil))
    func theCaptureSamplesMatchTheirDecodedMaps() async throws {
        try await check(try #require(CaptureSamples.folder))
    }

    private func check(_ folder: URL) async throws {
        let urls = CaptureModesOracle.images(in: folder)
        try #require(!urls.isEmpty)

        var counts: [String: Int] = [:]

        for url in urls {
            let modes = try CaptureModesOracle.read(url)
            let decoded = try await CaptureModesOracle.decoded(url)

            #expect(modes == decoded, "\(url.path)")

            for (mode, name) in [(CaptureModes.raw, "raw"), (.hdr, "hdr"), (.portrait, "portrait"), (.livePhoto, "live")]
                where modes.contains(mode) {
                counts[name, default: 0] += 1
            }
        }

        Log.debug("\(urls.count) images in \(folder.lastPathComponent): \(counts.sorted { $0.key < $1.key })")
    }
}

enum CaptureModesOracle {
    struct Unreadable: Error {
        let url: URL
    }

    /// The detector's answer, through the same calls the app makes.
    static func read(_ url: URL) throws -> CaptureModes {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw Unreadable(url: url) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        return CaptureModes(source: source, primaryProperties: properties)
    }

    /// The modes found by decoding each map, rather than by reading the file's list of them.
    static func decoded(_ url: URL) async throws -> CaptureModes {
        try await BlockingCallLimiter.shared.run {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let identifier = CGImageSourceGetType(source) as String?
            else { throw Unreadable(url: url) }

            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            let makerApple = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any]
            var modes: CaptureModes = []

            if let identifier = makerApple?["17"] as? String, !identifier.isEmpty {
                modes.insert(.livePhoto)
            }

            if UTType(identifier)?.conforms(to: .rawImage) == true {
                modes.insert(.raw)
                return modes
            }

            let primary = CGImageSourceGetPrimaryImageIndex(source)
            func has(_ type: CFString) -> Bool {
                CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, primary, type) != nil
            }

            var gainMaps = [kCGImageAuxiliaryDataTypeHDRGainMap]
            if #available(macOS 15, iOS 18, *) {
                gainMaps.append(kCGImageAuxiliaryDataTypeISOGainMap)
            }

            if gainMaps.contains(where: has) {
                modes.insert(.hdr)
            }

            if has(kCGImageAuxiliaryDataTypeDisparity) || has(kCGImageAuxiliaryDataTypeDepth) {
                modes.insert(.portrait)
            }

            return modes
        }
    }

    /// Every file ImageIO reads as an image under `folder`, recursively.
    static func images(in folder: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        )

        return (enumerator?.allObjects as? [URL] ?? []).filter { url in
            guard !url.hasDirectoryPath,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let identifier = CGImageSourceGetType(source) as String?,
                  let type = UTType(identifier)
            else { return false }

            return type.conforms(to: .image) && !type.conforms(to: .pdf) && CGImageSourceGetCount(source) > 0
        }
        .sorted { $0.path < $1.path }
    }
}
