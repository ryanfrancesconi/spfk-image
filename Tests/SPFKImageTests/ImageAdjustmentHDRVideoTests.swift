// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import AVFoundation
import CoreImage
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKImage

/// The tone-curve steps on HLG video, measured as 10-bit video-range luma codes, where SDR reference
/// white is 721 and anything above it is HDR headroom.
@Suite(.tags(.file))
struct ImageAdjustmentHDRVideoTests {
    struct Luma {
        var peak: Int
        var p999: Int
    }

    /// Luma of every frame of the HLG fixture after `adjustments`, through a Core Image composition.
    static func luma(_ adjustments: ImageAdjustmentDescription) async throws -> Luma {
        let asset = AVURLAsset(url: TestBundleResources.shared.hlg_pattern_mov)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)

        let composition = try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            // A clamp far outside any value makes a neutral description render too, rather than pass
            // the decoded frame through, so every case goes through the same conversions.
            let rendered = request.sourceImage.applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: -100, y: -100, z: -100, w: 0),
                "inputMaxComponents": CIVector(x: 100, y: 100, z: 100, w: 1),
            ])
            let output = ImageAdjustmentRenderer.apply(adjustments, to: rendered)
            request.finish(with: output, context: nil)
        }
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_2020
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_2100_HLG
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_2020

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        ])
        output.videoComposition = composition
        reader.add(output)
        try #require(reader.startReading())

        // `copyNextSampleBuffer` blocks its thread on the decoder, so it takes a slot as an encode does.
        let histogram = await BlockingCallLimiter.shared.run { Self.histogram(of: output) }

        try #require(reader.status == .completed)
        return try Self.luma(histogram: histogram)
    }

    /// Each luma code's pixel count across every frame.
    static func histogram(of output: AVAssetReaderOutput) -> [Int] {
        var histogram = [Int](repeating: 0, count: 1024)

        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

            guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { continue }
            let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
            let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
            let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)

            for y in 0 ..< height {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt16.self)
                for x in 0 ..< width {
                    histogram[Int(row[x] >> 6)] += 1
                }
            }
        }

        return histogram
    }

    static func luma(histogram: [Int]) throws -> Luma {
        let total = histogram.reduce(0, +)
        try #require(total > 0)
        let peak = histogram.lastIndex { $0 > 0 } ?? 0

        var above = 0
        var p999 = peak
        for code in stride(from: 1023, through: 0, by: -1) {
            above += histogram[code]
            if Double(above) > Double(total) * 0.001 {
                p999 = code
                break
            }
        }

        return Luma(peak: peak, p999: p999)
    }

    /// HLG's SDR reference white, signal 0.75, as a 10-bit video-range luma code.
    static let sdrWhite = 721

    @Test func theFixtureHasHeadroom() async throws {
        let source = try await Self.luma(ImageAdjustmentDescription())
        #expect(source.peak > Self.sdrWhite)
    }

    enum Step: String, CaseIterable, CustomTestStringConvertible {
        case brightness, whitePoint, blackPoint, levels, curves

        var adjustments: ImageAdjustmentDescription {
            switch self {
            case .brightness: .init(light: .init(brightness: 0.3))
            case .whitePoint: .init(light: .init(whitePoint: 0.3))
            case .blackPoint: .init(light: .init(blackPoint: 0.3))
            case .levels: .init(levels: .init(shadow: 0.2))
            case .curves: .init(curves: ImageToneCurves(rgb: [.init(x: 0, y: 0), .init(x: 0.5, y: 0.6), .init(x: 1, y: 1)]))
            }
        }

        var testDescription: String { rawValue }
    }

    @Test(arguments: [Step.brightness, .whitePoint])
    func brighteningCurvesKeepThePeak(_ step: Step) async throws {
        let source = try await Self.luma(ImageAdjustmentDescription())
        let adjusted = try await Self.luma(step.adjustments)
        #expect(adjusted.peak >= source.peak)
    }

    @Test(arguments: [Step.blackPoint, .levels, .curves])
    func otherCurvesKeepTheHighlights(_ step: Step) async throws {
        let source = try await Self.luma(ImageAdjustmentDescription())
        let adjusted = try await Self.luma(step.adjustments)
        #expect(adjusted.peak >= source.p999)
    }
}
