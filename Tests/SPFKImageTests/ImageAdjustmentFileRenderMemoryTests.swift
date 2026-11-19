// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKImage

/// Save over many cropped files holds no more memory at the end than after its first files.
@Suite(.tags(.file, .slow))
final class ImageAdjustmentFileRenderMemoryTests: BinTestCase {
    @Test func croppedSavesHoldNoMemoryPerFile() async throws {
        guard #available(macOS 15, iOS 18, *) else { return }

        let input = try ImageFormatConverterMemoryTests.photoSizedGainMappedHEIC(in: bin)
        try #require(AdjustmentFileFixtures.GainMapFormat.iso.info(input) != nil)

        let renderer = ImageAdjustmentRenderer()
        let bin = bin

        let grown = try await retainedMemoryMB(warmUp: 16, measured: 60, width: 8) { index in
            let output = bin.appendingPathComponent("saved-\(index).heic")
            try await renderer.renderFile(
                ImageAdjustmentDescription(), crop: ImageFormatConverterMemoryTests.photoCrop, source: input, destination: output
            )
            try FileManager.default.removeItem(at: output)
        }

        #expect(grown < 100, "grew \(Int(grown)) MB over 60 files")
    }
}
