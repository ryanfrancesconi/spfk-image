// Copyright Ryan Francesconi. All Rights Reserved.

import CoreGraphics
import Foundation

/// Summary statistics of an image drawn into 8-bit sRGB, in levels (0-255).
struct ImageStatistics {
    let width: Int
    let height: Int
    let meanRed: Double
    let meanGreen: Double
    let meanBlue: Double
    let meanLuminance: Double
    let luminanceStandardDeviation: Double
    /// 10th and 90th percentile luminance.
    let darkLuminance: Double
    let brightLuminance: Double
    /// Mean of max(r, g, b) - min(r, g, b) per pixel; 0 for a grayscale image.
    let meanChannelSpread: Double
    /// Mean squared response of a 4-neighbor Laplacian over luminance.
    let edgeEnergy: Double

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        let pixelCount = width * height

        guard pixelCount > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: pixelCount * 4)

        var sumR = 0.0, sumG = 0.0, sumB = 0.0, sumL = 0.0, sumL2 = 0.0, sumSpread = 0.0
        var histogram = [Int](repeating: 0, count: 256)
        var luminance = [Double](repeating: 0, count: pixelCount)

        for i in 0 ..< pixelCount {
            let r = Double(pixels[i * 4]), g = Double(pixels[i * 4 + 1]), b = Double(pixels[i * 4 + 2])
            let l = 0.2126 * r + 0.7152 * g + 0.0722 * b
            sumR += r; sumG += g; sumB += b; sumL += l; sumL2 += l * l
            sumSpread += max(r, g, b) - min(r, g, b)
            histogram[min(255, Int(l.rounded()))] += 1
            luminance[i] = l
        }

        let n = Double(pixelCount)
        meanRed = sumR / n
        meanGreen = sumG / n
        meanBlue = sumB / n
        meanLuminance = sumL / n
        luminanceStandardDeviation = sqrt(max(0, sumL2 / n - meanLuminance * meanLuminance))
        meanChannelSpread = sumSpread / n
        darkLuminance = Self.percentile(0.1, of: histogram, count: pixelCount)
        brightLuminance = Self.percentile(0.9, of: histogram, count: pixelCount)

        var energy = 0.0
        var samples = 0
        if width > 2, height > 2 {
            for y in 1 ..< height - 1 {
                for x in 1 ..< width - 1 {
                    let i = y * width + x
                    let response = 4 * luminance[i] - luminance[i - 1] - luminance[i + 1]
                        - luminance[i - width] - luminance[i + width]
                    energy += response * response
                    samples += 1
                }
            }
        }
        edgeEnergy = samples > 0 ? energy / Double(samples) : 0
    }

    private static func percentile(_ fraction: Double, of histogram: [Int], count: Int) -> Double {
        let target = Int(Double(count) * fraction)
        var running = 0
        for (level, pixels) in histogram.enumerated() {
            running += pixels
            if running > target { return Double(level) }
        }
        return 255
    }
}
