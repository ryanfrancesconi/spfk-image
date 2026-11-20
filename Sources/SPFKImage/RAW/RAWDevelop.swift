// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Develops a RAW file through `CIRAWFilter`, with Exposure, Temperature, Tint and Noise Reduction
/// applied inside the develop, where the sensor's headroom is still available.
///
/// The rest of an adjustment comes back in ``Developed/remaining``, for
/// ``ImageAdjustmentRenderer/apply(_:to:sourceScale:grainSeed:)`` to run on the developed image.
public struct RAWDevelop: Sendable {
    public struct Options: Sendable, Hashable {
        /// The output's size relative to the full image, limited to 0.001...1.
        public var scaleFactor: Double {
            didSet { scaleFactor = Self.limit(scaleFactor) }
        }

        public var isDraft: Bool

        /// False develops the stored, unoriented pixels.
        public var appliesFileOrientation: Bool

        public init(scaleFactor: Double = 1, isDraft: Bool = false, appliesFileOrientation: Bool = true) {
            self.scaleFactor = Self.limit(scaleFactor)
            self.isDraft = isDraft
            self.appliesFileOrientation = appliesFileOrientation
        }

        private static func limit(_ value: Double) -> Double {
            value.isFinite ? min(max(value, 0.001), 1) : 1
        }
    }

    /// A developed image, upright unless the options say otherwise, and the adjustments the develop
    /// did not take.
    public struct Developed: Sendable {
        public let image: CIImage
        public let remaining: ImageAdjustmentDescription
    }

    /// Whether ImageIO reads `source` as a RAW image. The content decides, never the extension.
    public static func isRAW(_ source: CGImageSource) -> Bool {
        guard let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier)
        else { return false }

        return type.conforms(to: .rawImage)
    }

    public static func isRAW(contentsOf url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return isRAW(source)
    }

    /// The file developed with `adjustments`. A nil `decoderVersion` uses the system's current default.
    public static func develop(
        contentsOf url: URL,
        adjustments: ImageAdjustmentDescription = ImageAdjustmentDescription(),
        decoderVersion: String? = nil,
        options: Options = Options()
    ) throws -> Developed {
        try Session(contentsOf: url, decoderVersion: decoderVersion).develop(adjustments, options: options)
    }

    /// The decoder versions the system can develop the file with, and the one it uses by default; nil
    /// when the file is not RAW.
    public static func decoderVersions(contentsOf url: URL) -> (supported: [String], current: String)? {
        guard isRAW(contentsOf: url), let filter = CIRAWFilter(imageURL: url) else { return nil }
        return (filter.supportedDecoderVersions.map(\.rawValue), filter.decoderVersion.rawValue)
    }
}
