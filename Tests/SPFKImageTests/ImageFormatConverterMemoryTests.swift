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

        func convert(_ count: Int, from start: Int) async throws {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in start ..< start + count {
                    if index - start >= 8 { try await group.next() }

                    group.addTask {
                        let output = bin.appendingPathComponent("out-\(index).heic")
                        let source = ImageConversionSource(input: input, output: output, options: options)
                        _ = try ImageFormatConverter(source: source).convert()
                        try FileManager.default.removeItem(at: output)
                    }
                }
                try await group.waitForAll()
            }
        }

        // Caches and pools fill on the first files; growth after that is what is kept per file.
        try await convert(16, from: 0)
        let settled = Self.footprintMB()
        try await convert(60, from: 16)
        let grown = Self.footprintMB() - settled

        #expect(grown < 100, "grew \(Int(grown)) MB over 60 files")
    }

    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
