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
    /// Photo-sized, so that anything kept per file is large against the noise of the suites running alongside.
    private func photoSizedGainMappedHEIC() throws -> URL {
        let url = bin.appendingPathComponent("photo-gain-map.heic")
        let extent = CGRect(x: 0, y: 0, width: 4032, height: 3024)

        let checkerboard = CIFilter.checkerboardGenerator()
        checkerboard.width = 96
        checkerboard.color0 = CIColor(red: 0.8, green: 0.5, blue: 0.3)
        checkerboard.color1 = CIColor(red: 0.2, green: 0.3, blue: 0.6)

        let gradient = CIFilter.radialGradient()
        gradient.center = CGPoint(x: 1008, y: 756)
        gradient.radius1 = 756
        gradient.color0 = .white
        gradient.color1 = .black

        guard let base = checkerboard.outputImage?.cropped(to: extent),
              let gainMap = gradient.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: 2016, height: 1512)),
              let space = CGColorSpace(name: CGColorSpace.displayP3),
              let data = CIContext().heifRepresentation(
                  of: base, format: .RGBA8, colorSpace: space, options: [.hdrGainMapImage: gainMap]
              )
        else { throw AdjustmentFileFixtures.GenerationError(message: "no gain-mapped HEIC") }

        try data.write(to: url)
        return url
    }

    @Test func carryingGainMapsHoldsNoMemoryPerFile() async throws {
        let input = try photoSizedGainMappedHEIC()
        let sourceImage = try #require(CGImageSourceCreateWithURL(input as CFURL, nil))
        try #require(CGImageSourceCopyAuxiliaryDataInfoAtIndex(sourceImage, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil)

        let options = ImageConversionOptions(format: UTType.heic.identifier)
        let bin = bin

        let grown = try await retainedMemoryMB(warmUp: 16, measured: 60, width: 8) { index in
            let output = bin.appendingPathComponent("out-\(index).heic")
            let source = ImageConversionSource(input: input, output: output, options: options)
            _ = try ImageFormatConverter(source: source).convert()
            try FileManager.default.removeItem(at: output)
        }

        #expect(grown < 100, "grew \(Int(grown)) MB over 60 files")
    }
}
