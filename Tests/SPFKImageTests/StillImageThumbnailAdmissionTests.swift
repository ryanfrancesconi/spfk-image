// Copyright Ryan Francesconi. All Rights Reserved.

import CoreGraphics
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKImage

@Suite(.tags(.file))
struct StillImageThumbnailAdmissionTests {
    private static func bytes(_ image: CGImage?) -> Data? {
        image?.dataProvider?.data as Data?
    }

    @Test func aJPEGDecodesAsMakeDoes() async throws {
        let url = TestBundleResources.shared.songbird

        let admitted = try #require(await StillImageThumbnail.admitted(url: url, maxPixelSize: 128, allowsEmbeddedThumbnail: false))
        let made = StillImageThumbnail.make(url: url, maxPixelSize: 128, allowsEmbeddedThumbnail: false)

        #expect(Self.bytes(admitted) == Self.bytes(made))
    }

    @Test(.tags(.rawDevelop), .enabled(if: RAWSamples.folder != nil), arguments: [false, true])
    func aRAWDecodesAsMakeDoes(allowsEmbeddedThumbnail: Bool) async throws {
        let url = try #require(RAWSamples.url("DSCF4449.RAF"))

        let admitted = try #require(await StillImageThumbnail.admitted(
            url: url, maxPixelSize: 128, allowsEmbeddedThumbnail: allowsEmbeddedThumbnail
        ))
        let made = StillImageThumbnail.make(url: url, maxPixelSize: 128, allowsEmbeddedThumbnail: allowsEmbeddedThumbnail)

        #expect(Self.bytes(admitted) == Self.bytes(made))
    }

    /// Unadmitted, this many full decodes of this file from a task group hang with none complete.
    @Test(.tags(.rawDevelop, .slow), .enabled(if: RAWSamples.folder != nil))
    func moreRAWDecodesThanCooperativeThreadsAllComplete() async throws {
        let url = try #require(RAWSamples.url("DSCF4449.RAF"))
        let count = ProcessInfo.processInfo.activeProcessorCount * 2

        let decoded = await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< count {
                group.addTask {
                    await StillImageThumbnail.admitted(url: url, maxPixelSize: 128, allowsEmbeddedThumbnail: false) != nil
                }
            }

            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }

        #expect(decoded == count)
    }
}
