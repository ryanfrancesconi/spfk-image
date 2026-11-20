// Copyright Ryan Francesconi. All Rights Reserved.

import CoreImage
import Foundation
import ImageIO
import Testing

/// Measures of a RAW develop, read from an `RGBAf` render in Display P3.
struct RAWMeasure {
    /// The scale the develop measures render at, as a `RAWDevelop.Options.scaleFactor`.
    static let scaleFactor: Double = 0.25

    static let context = CIContext()

    let width: Int
    let height: Int
    let pixels: [Float]

    init(_ image: CIImage) throws {
        let bounds = image.extent.integral
        try #require(!bounds.isInfinite && !bounds.isEmpty)

        let width = Int(bounds.width)
        let height = Int(bounds.height)

        var pixels = [Float](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))

        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            Self.context.render(image, toBitmap: base, rowBytes: width * 16, bounds: bounds, format: .RGBAf, colorSpace: space)
        }

        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// The file's primary image, upright, drawn at `scale`.
    init(contentsOf url: URL, scale: Double = scaleFactor, keepingLeftWidth: Int? = nil) throws {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        var image = CIImage(cgImageSource: source, index: CGImageSourceGetPrimaryImageIndex(source), options: [.applyOrientationProperty: true])

        if let keepingLeftWidth {
            let extent = image.extent
            image = image.cropped(to: CGRect(x: extent.minX, y: extent.minY, width: CGFloat(keepingLeftWidth), height: extent.height))
        }

        let origin = image.extent.origin
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])

        try self.init(scaled)
    }

    private var pixelCount: Int { width * height }

    /// The fraction of pixels with any channel at or above 0.999.
    var clippedFraction: Double {
        var clipped = 0
        for i in 0 ..< pixelCount where pixels[i * 4] >= 0.999 || pixels[i * 4 + 1] >= 0.999 || pixels[i * 4 + 2] >= 0.999 {
            clipped += 1
        }
        return Double(clipped) / Double(pixelCount)
    }

    var meanRed: Double { mean(channel: 0) }
    var meanGreen: Double { mean(channel: 1) }
    var meanBlue: Double { mean(channel: 2) }

    var meanLuminance: Double {
        0.2126 * meanRed + 0.7152 * meanGreen + 0.0722 * meanBlue
    }

    private func mean(channel: Int) -> Double {
        var sum = 0.0
        for i in 0 ..< pixelCount { sum += Double(pixels[i * 4 + channel]) }
        return sum / Double(pixelCount)
    }

    /// The largest difference in any color channel, or nil when the sizes differ.
    func largestDifference(from other: RAWMeasure) -> Double? {
        guard width == other.width, height == other.height else { return nil }

        var largest: Float = 0
        for i in 0 ..< pixels.count where i % 4 != 3 {
            largest = max(largest, abs(pixels[i] - other.pixels[i]))
        }
        return Double(largest)
    }

    /// The share of pixels whose largest channel difference exceeds `threshold`, or nil when the sizes differ.
    func shareDiffering(from other: RAWMeasure, by threshold: Double) -> Double? {
        guard width == other.width, height == other.height else { return nil }

        var differing = 0
        for pixel in 0 ..< pixelCount {
            let i = pixel * 4
            if (0 ..< 3).contains(where: { Double(abs(pixels[i + $0] - other.pixels[i + $0])) > threshold }) {
                differing += 1
            }
        }
        return Double(differing) / Double(pixelCount)
    }

    /// The mean difference across color channels, or nil when the sizes differ.
    func meanDifference(from other: RAWMeasure) -> Double? {
        guard width == other.width, height == other.height else { return nil }

        var sum = 0.0
        for i in 0 ..< pixels.count where i % 4 != 3 {
            sum += Double(abs(pixels[i] - other.pixels[i]))
        }
        return sum / Double(pixelCount * 3)
    }

    /// The mean absolute difference between `image` and a blurred copy: what noise reduction lowers.
    static func highFrequency(_ image: CIImage) throws -> Double {
        let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: 2).cropped(to: image.extent)
        return try #require(RAWMeasure(image).meanDifference(from: RAWMeasure(blurred)))
    }
}
