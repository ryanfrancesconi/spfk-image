// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import ImageIO

extension RAWDevelop {
    /// One file's `CIRAWFilter`, held so that a re-develop reuses its decode.
    ///
    /// Not `Sendable`: the owner uses it from one task at a time.
    public final class Session {
        private let filter: CIRAWFilter

        // The filter's own values before any develop, which each develop returns to when it sets nothing.
        private let asShotTemperature: Float
        private let asShotTint: Float
        private let defaultExposure: Float
        private let defaultNoiseReduction: Float
        private let fileOrientation: CGImagePropertyOrientation
        private let supportsLuminanceNoiseReduction: Bool

        public init(contentsOf url: URL, decoderVersion: String? = nil) throws {
            guard RAWDevelop.isRAW(contentsOf: url), let filter = CIRAWFilter(imageURL: url) else {
                throw RAWDevelopError.unreadable
            }

            // Before anything else is read: the as-shot values may depend on the version.
            if let decoderVersion {
                guard let version = filter.supportedDecoderVersions.first(where: { $0.rawValue == decoderVersion }) else {
                    throw RAWDevelopError.unsupportedDecoderVersion(decoderVersion)
                }
                filter.decoderVersion = version
            }

            self.filter = filter
            asShotTemperature = filter.neutralTemperature
            asShotTint = filter.neutralTint
            defaultExposure = filter.exposure
            defaultNoiseReduction = filter.luminanceNoiseReductionAmount
            fileOrientation = filter.orientation
            supportsLuminanceNoiseReduction = filter.isLuminanceNoiseReductionSupported
        }

        /// The file developed with `adjustments`. Every value a previous call set is set again, so
        /// nothing carries over from one call to the next.
        public func develop(_ adjustments: ImageAdjustmentDescription, options: Options = Options()) throws -> Developed {
            let parameters = Parameters(
                adjustments,
                asShotTemperature: Double(asShotTemperature),
                asShotTint: Double(asShotTint),
                supportsLuminanceNoiseReduction: supportsLuminanceNoiseReduction
            )

            // Assigned only on a change, so an untouched filter develops exactly as a new one does.
            let exposure = parameters.exposure == 0 ? defaultExposure : Float(parameters.exposure)
            if filter.exposure != exposure { filter.exposure = exposure }

            let temperature = parameters.neutralTemperature.map(Float.init) ?? asShotTemperature
            let tint = parameters.neutralTint.map(Float.init) ?? asShotTint
            if filter.neutralTemperature != temperature || filter.neutralTint != tint {
                filter.neutralTemperature = temperature
                filter.neutralTint = tint
            }

            if supportsLuminanceNoiseReduction {
                let amount = parameters.luminanceNoiseReduction.map(Float.init) ?? defaultNoiseReduction
                if filter.luminanceNoiseReductionAmount != amount { filter.luminanceNoiseReductionAmount = amount }
            }

            let scaleFactor = Float(options.scaleFactor)
            if filter.scaleFactor != scaleFactor { filter.scaleFactor = scaleFactor }
            if filter.isDraftModeEnabled != options.isDraft { filter.isDraftModeEnabled = options.isDraft }

            let orientation = options.appliesFileOrientation ? fileOrientation : .up
            if filter.orientation != orientation { filter.orientation = orientation }

            guard let image = filter.outputImage else { throw RAWDevelopError.developFailed }

            return Developed(image: image, remaining: parameters.remaining)
        }
    }
}
