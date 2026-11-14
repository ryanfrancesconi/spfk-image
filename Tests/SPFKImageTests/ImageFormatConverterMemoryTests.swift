// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import SPFKBase
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

/// A batch of thousands holds no more memory at the end than after its first files.
@Suite(.tags(.file, .slow, .conversion))
final class ImageFormatConverterMemoryTests: BinTestCase {
    /// Photo-sized, so that anything kept per file is large against the noise of the suites running alongside. ISO
    /// only: both formats are carried by the same loop.
    @available(macOS 15, iOS 18, *)
    private func photoSizedGainMappedHEIC() throws -> URL {
        let url = bin.appendingPathComponent("photo-gain-map.heic")
        let extent = CGRect(x: 0, y: 0, width: 4032, height: 3024)

        let checkerboard = CIFilter.checkerboardGenerator()
        checkerboard.width = 96
        checkerboard.color0 = CIColor(red: 0.8, green: 0.5, blue: 0.3)
        checkerboard.color1 = CIColor(red: 0.2, green: 0.3, blue: 0.6)

        guard let base = checkerboard.outputImage?.cropped(to: extent) else {
            throw AdjustmentFileFixtures.GenerationError(message: "no checkerboard")
        }

        try AdjustmentFileFixtures.writeGainMapped(base, type: .heic, format: .iso, to: url)
        return url
    }

    @Test func carryingGainMapsHoldsNoMemoryPerFile() async throws {
        guard #available(macOS 15, iOS 18, *) else { return }

        let input = try photoSizedGainMappedHEIC()
        try #require(AdjustmentFileFixtures.GainMapFormat.iso.info(input) != nil)

        let options = ImageConversionOptions(format: UTType.heic.identifier)
        let bin = bin

        let grown = try await retainedMemoryMB(warmUp: 16, measured: 60, width: 8) { index in
            let output = bin.appendingPathComponent("out-\(index).heic")
            let source = ImageConversionSource(input: input, output: output, options: options)
            _ = try await ImageFormatConverter(source: source).convert()
            try FileManager.default.removeItem(at: output)
        }

        #expect(grown < 100, "grew \(Int(grown)) MB over 60 files")
    }
}
