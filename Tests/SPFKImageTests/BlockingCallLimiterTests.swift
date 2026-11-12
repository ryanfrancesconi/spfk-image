// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKBase
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

@Suite(.tags(.file))
final class BlockingCallLimiterTests: BinTestCase {
    /// Auto analysis and AV1 encodes, more at once than there are cores. Ungated, this many hang with
    /// none complete.
    @Test func moreAutoAndAVIFCallsThanCoresAllFinish() async throws {
        let avif = try #require(UTType("public.avif"))
        let jpeg = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 1, in: bin)
        let count = ProcessInfo.processInfo.activeProcessorCount + 2

        let finished = try await withThrowingTaskGroup(of: Bool.self) { group in
            for index in 0 ..< count {
                group.addTask { [bin] in
                    if index.isMultiple(of: 2) {
                        return await ImageAdjustmentRenderer.autoAdjustments(contentsOf: TestBundleResources.shared.songbird) != nil
                    }

                    let output = bin.appending(component: "out-\(index)").appendingPathExtension(for: avif)
                    let options = ImageConversionOptions(format: avif.identifier)
                    _ = try await ImageFormatConverter(source: ImageConversionSource(input: jpeg, output: output, options: options)).convert()
                    return true
                }
            }

            return try await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }

        #expect(finished == count)
    }

    /// AVIF renders alternating with AVIF conversions, more at once than there are cores. Ungated, this many
    /// hang with none complete.
    @Test func moreAVIFRendersAndConversionsThanCoresAllFinish() async throws {
        let avif = try #require(UTType("public.avif"))
        let jpeg = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 1, in: bin)
        let avifSource = try AdjustmentFileFixtures.tagged(avif, orientation: 1, in: bin)
        let adjustments = ImageAdjustmentDescription(light: .init(exposure: 1))
        let count = ProcessInfo.processInfo.activeProcessorCount + 2

        let finished = try await withThrowingTaskGroup(of: Bool.self) { group in
            for index in 0 ..< count {
                group.addTask { [bin] in
                    let output = bin.appending(component: "out-\(index)").appendingPathExtension(for: avif)

                    if index.isMultiple(of: 2) {
                        try await ImageAdjustmentRenderer().renderFile(adjustments, source: avifSource, destination: output)
                        return true
                    }

                    let options = ImageConversionOptions(format: avif.identifier)
                    _ = try await ImageFormatConverter(source: ImageConversionSource(input: jpeg, output: output, options: options)).convert()
                    return true
                }
            }

            return try await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }

        #expect(finished == count)
    }
}
