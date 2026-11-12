// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import os
import Testing
import UniformTypeIdentifiers

@testable import SPFKImage

final class ImageRenderStageTests {
    private let directory: URL
    private let renderer = ImageAdjustmentRenderer()
    private let brighter = ImageAdjustmentDescription(light: .init(exposure: 1))
    private let stages = OSAllocatedUnfairLock<[ImageRenderStage]>(initialState: [])

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spfk-image-render-stage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private var record: @Sendable (ImageRenderStage) -> Void {
        { [stages] stage in stages.withLock { $0.append(stage) } }
    }

    @Test func stagesAreReportedInOrder() async throws {
        let source = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 1, in: directory)

        try await renderer.renderFile(
            brighter, source: source, destination: directory.appendingPathComponent("out.jpg"), stage: record
        )

        #expect(stages.withLock { $0 } == [.rendering, .encoding, .verifying])
    }

    /// The read-back fails during `.verifying`, the last stage.
    @Test func nothingIsReportedAfterAThrow() throws {
        let source = try AdjustmentFileFixtures.tagged(.jpeg, orientation: 6, in: directory)

        #expect(throws: ImageAdjustmentRenderError.readBackMismatch) {
            try self.renderer.renderFile(
                self.brighter, source: source, destination: self.directory.appendingPathComponent("out.jpg"),
                quality: 0.9, expectedOrientation: 1, stage: self.record
            )
        }

        #expect(stages.withLock { $0 } == [.rendering, .encoding, .verifying])
    }

    @Test func aRefusedSourceReportsNoStage() async throws {
        let source = try AdjustmentFileFixtures.twoPageTIFF(in: directory)

        await #expect(throws: ImageAdjustmentRenderError.multipleImages) {
            try await self.renderer.renderFile(
                self.brighter, source: source, destination: self.directory.appendingPathComponent("out.tiff"),
                stage: self.record
            )
        }

        #expect(stages.withLock { $0 }.isEmpty)
    }
}
