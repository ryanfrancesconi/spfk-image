// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKBase
import SPFKTesting
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

@Suite(.tags(.file))
final class BlockingCallLimiterTests: BinTestCase {
    private final class Occupancy: @unchecked Sendable {
        private let lock = NSLock()
        private var current = 0
        private(set) var peak = 0

        func enter() { lock.withLock { current += 1; peak = max(peak, current) } }
        func leave() { lock.withLock { current -= 1 } }
    }

    @Test func noMoreThanTheWidthRunAtOnce() async {
        let limiter = BlockingCallLimiter(width: 2)
        let occupancy = Occupancy()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 8 {
                group.addTask {
                    await limiter.run {
                        occupancy.enter()
                        Thread.sleep(forTimeInterval: 0.02)
                        occupancy.leave()
                    }
                }
            }
        }

        #expect(occupancy.peak == 2)
    }

    @Test func aThrowingBodyReleasesItsSlot() async {
        let limiter = BlockingCallLimiter(width: 1)
        struct Failure: Error {}

        await #expect(throws: Failure.self) {
            try await limiter.run { throw Failure() }
        }

        #expect(await limiter.run { true })
    }

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
}
