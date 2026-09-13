// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreGraphics
import CoreImage
import Foundation
import SPFKBase

extension CGImage {
    /// A content hash over the image's geometry and its whole pixel buffer, for deduplicating
    /// images a store has already written.
    ///
    /// The buffer goes through `combine(bytes:)` rather than `combine(_: Data)`, which hashes
    /// only a leading slice — covers sharing a plain band above the artwork collide under it.
    public var fingerprint: Int? {
        guard let data = dataProvider?.data as Data? else { return nil }

        var hasher = Hasher()
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(bytesPerRow)
        data.withUnsafeBytes { hasher.combine(bytes: $0) }

        return hasher.finalize()
    }

    public func scaled(to size: CGSize) -> CGImage? {
        let width: Int = Int(size.width)
        let height: Int = Int(size.height)

        var binfo = bitmapInfo
        binfo.pixelFormat = .packed
        binfo.byteOrder = .orderDefault
        binfo.alpha = .premultipliedLast

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: binfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high

        context.draw(
            self,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )

        return context.makeImage()
    }

    /// Compares the raw pixel data of two images.
    ///
    /// Returns `true` when both images have the same dimensions and their
    /// `CGDataProvider` byte sequences are identical. Returns `false` if
    /// dimensions differ or pixel data cannot be read from either image.
    public func hasEqualPixelData(_ other: CGImage) -> Bool {
        guard width == other.width, height == other.height else {
            return false
        }

        guard let selfData = dataProvider?.data as Data?,
              let otherData = other.dataProvider?.data as Data?
        else {
            return false
        }

        return selfData == otherData
    }

    public static func create(from data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw NSError(description: "CGImageSourceCreateWithData failed to create source")
        }

        // Get the first image from the source
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(description: "CGImageSourceCreateImageAtIndex 0 failed to create cgImage")
        }

        return cgImage
    }

    public static func contentsOf(url: URL) throws -> CGImage {
        try create(from: Data(contentsOf: url))
    }
}


extension CGImage {
    /// Side length of the grayscale grid a perceptual hash is computed over. 8 rows of 8
    /// comparisons gives exactly 64 bits.
    private static let perceptualHashSize = 8

    /// A 64-bit perceptual hash, for deciding whether two images *look* the same.
    ///
    /// Distinct from ``fingerprint``, which asks whether two images are byte-identical and is the
    /// right question for a store deduplicating what it has already written. This asks whether two
    /// images are the same picture, which is the right question for grouping album artwork: the
    /// same cover embedded across an album's tracks is routinely a different size in each file, or
    /// re-encoded by whatever tagger touched it last, and byte identity says those are unrelated.
    ///
    /// A difference hash (dHash): the image is reduced to a 9x8 grayscale grid and each pixel is
    /// compared with its right-hand neighbour, one bit per comparison. Chosen over an average hash
    /// because it encodes *gradients* rather than brightness relative to a mean, which is what
    /// keeps predominantly dark or flat covers -- of which there are many -- from collapsing into
    /// each other.
    ///
    /// Scale-independent by construction, since everything is resampled to the same grid first.
    ///
    /// Compare with ``perceptualDistance(to:)`` rather than `==`: re-encoding can flip a bit or two
    /// without changing what the image is.
    public var perceptualHash: UInt64? {
        let height = Self.perceptualHashSize
        // One extra column: each row yields `height` comparisons between adjacent pixels.
        let width = height + 1

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0, // let CoreGraphics choose an aligned stride
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        // Deliberately not `.high`: heavier interpolation makes the result depend more on the
        // source resolution, which is exactly what this has to be independent of.
        context.interpolationQuality = .medium
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }

        let stride = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: stride * height)

        var hash: UInt64 = 0
        var bit = 0

        for y in 0 ..< height {
            let row = y * stride
            for x in 0 ..< (width - 1) {
                if pixels[row + x] > pixels[row + x + 1] {
                    hash |= (1 << UInt64(bit))
                }
                bit += 1
            }
        }

        return hash
    }

    /// Number of differing bits between two images' perceptual hashes, or `nil` if either could not
    /// be hashed. `0` means the two reduce to an identical gradient grid.
    public func perceptualDistance(to other: CGImage) -> Int? {
        guard let a = perceptualHash, let b = other.perceptualHash else { return nil }
        return (a ^ b).nonzeroBitCount
    }

    /// Largest ``perceptualDistance(to:)`` still treated as the same picture.
    ///
    /// Measured against the test fixtures rather than picked from a reference: the same image as
    /// JPEG, HEIC and WebP lands at 0-1, and rescaled between 512px and 32px at 1-3, while two
    /// genuinely different images sit at 34-36. Ten is an order of magnitude clear of the noise and
    /// nowhere near the signal, so the exact value is not load-bearing -- there is simply nothing
    /// in between.
    public static let perceptualTolerance = 10

    /// Whether two images are the same picture, allowing for re-encoding and resizing.
    ///
    /// The question album-artwork grouping needs to ask: the same cover across an album's tracks is
    /// routinely a different size in each file, or re-encoded by whatever tagger touched it last.
    /// `nil` hashes (an image whose pixels cannot be read) compare as not similar, so an unreadable
    /// image never silently merges into a group.
    public func isPerceptuallySimilar(to other: CGImage, tolerance: Int = perceptualTolerance) -> Bool {
        guard let distance = perceptualDistance(to: other) else { return false }
        return distance <= tolerance
    }
}
