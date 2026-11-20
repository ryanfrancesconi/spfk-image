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
        private let defaultColorNoiseReduction: Float
        private let defaultMoireReduction: Float
        private let fileOrientation: CGImagePropertyOrientation
        private let supportsLuminanceNoiseReduction: Bool
        private let supportsColorNoiseReduction: Bool
        private let supportsMoireReduction: Bool

        /// The RAW section's parameters this file's develop supports.
        public var supportedDevelopParameters: Set<ImageAdjustmentDescription.Parameter> {
            var supported = Set<ImageAdjustmentDescription.Parameter>()
            if supportsColorNoiseReduction { supported.insert(.colorNoiseReduction) }
            if supportsMoireReduction { supported.insert(.moireReduction) }
            return supported
        }

        /// The develop's full size, before orientation.
        public var nativeSize: CGSize { filter.nativeSize }

        private var fileValues: FileValues {
            FileValues(
                asShotTemperature: Double(asShotTemperature),
                asShotTint: Double(asShotTint),
                colorNoiseReduction: Double(defaultColorNoiseReduction),
                moireReduction: Double(defaultMoireReduction),
                supportsLuminanceNoiseReduction: supportsLuminanceNoiseReduction,
                supportsColorNoiseReduction: supportsColorNoiseReduction,
                supportsMoireReduction: supportsMoireReduction
            )
        }

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
            defaultColorNoiseReduction = filter.colorNoiseReductionAmount
            defaultMoireReduction = filter.moireReductionAmount
            fileOrientation = filter.orientation
            supportsLuminanceNoiseReduction = filter.isLuminanceNoiseReductionSupported
            supportsColorNoiseReduction = filter.isColorNoiseReductionSupported
            supportsMoireReduction = filter.isMoireReductionSupported
        }

        /// The file developed with `adjustments`. Every value a previous call set is set again, so
        /// nothing carries over from one call to the next.
        public func develop(_ adjustments: ImageAdjustmentDescription, options: Options = Options()) throws -> Developed {
            let parameters = Parameters(adjustments, file: fileValues)

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

            if supportsColorNoiseReduction {
                let amount = parameters.colorNoiseReduction.map(Float.init) ?? defaultColorNoiseReduction
                if filter.colorNoiseReductionAmount != amount { filter.colorNoiseReductionAmount = amount }
            }

            if supportsMoireReduction {
                let amount = parameters.moireReduction.map(Float.init) ?? defaultMoireReduction
                if filter.moireReductionAmount != amount { filter.moireReductionAmount = amount }
            }

            apply(options)

            guard let image = filter.outputImage else { throw RAWDevelopError.developFailed }

            return Developed(image: image, remaining: parameters.remaining)
        }

        /// Temperature and Tint, in slider units, that make the point neutral. The point is in
        /// fractions of the developed image, origin top left.
        ///
        /// The developed image is the one `develop` returns with `options`, before any pending
        /// orientation edit. A point outside 0...1 throws.
        public func whiteBalance(atUnitPoint point: CGPoint, options: Options = Options()) throws -> (temperature: Double, tint: Double) {
            guard (0 ... 1).contains(point.x), (0 ... 1).contains(point.y) else {
                throw RAWDevelopError.pointOutsideImage
            }

            apply(options)

            guard let extent = filter.outputImage?.extent, !extent.isEmpty, !extent.isInfinite else {
                throw RAWDevelopError.developFailed
            }

            let previousTemperature = filter.neutralTemperature
            let previousTint = filter.neutralTint

            // In the output's own coordinates: Core Image's, origin bottom left, at the current scale.
            filter.neutralLocation = CGPoint(
                x: extent.minX + point.x * extent.width,
                y: extent.minY + (1 - point.y) * extent.height
            )

            let picked = (temperature: Double(filter.neutralTemperature), tint: Double(filter.neutralTint))

            filter.neutralTemperature = previousTemperature
            filter.neutralTint = previousTint

            return RAWDevelop.whiteBalance(
                neutralTemperature: picked.temperature,
                neutralTint: picked.tint,
                asShotTemperature: Double(asShotTemperature),
                asShotTint: Double(asShotTint)
            )
        }

        private func apply(_ options: Options) {
            let scaleFactor = Float(options.scaleFactor)
            if filter.scaleFactor != scaleFactor { filter.scaleFactor = scaleFactor }
            if filter.isDraftModeEnabled != options.isDraft { filter.isDraftModeEnabled = options.isDraft }

            let orientation = options.appliesFileOrientation ? fileOrientation : .up
            if filter.orientation != orientation { filter.orientation = orientation }
        }
    }
}
