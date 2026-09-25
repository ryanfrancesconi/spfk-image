// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

#if os(macOS)
    import CoreGraphics
    import Foundation
    import SPFKBase
    import SPFKTesting
    import Testing

    @testable import SPFKImage

    /// Deciding whether two images are the same *picture*, as opposed to the same *bytes*.
    ///
    /// The case this exists for: album artwork embedded across an album's tracks, where each file
    /// routinely carries a different size or a different encoding of one cover. `fingerprint` hashes
    /// dimensions and the first 256 bytes of pixel data, so it reports every one of those as a
    /// distinct image -- which is why ShadowTag's artwork grid showed the same cover more than once.
    @Suite(.tags(.file))
    struct CGImagePerceptualHashTests {
        private func image(_ url: URL) throws -> CGImage {
            try CGImage.contentsOf(url: url)
        }

        private var sharkJPEG: URL { TestBundleResources.shared.sharksandwich }
        private var sharkHEIC: URL { TestBundleResources.shared.sharksandwich_heic }
        private var sharkWebP: URL { TestBundleResources.shared.sharksandwich_webp }
        private var songbird: URL { TestBundleResources.shared.songbird }

        // MARK: - The bug this fixes

        /// **The same picture in three container formats.** Measured distances are 0-1.
        @Test func reencodingDoesNotChangeThePicture() throws {
            let jpeg = try image(sharkJPEG)
            let heic = try image(sharkHEIC)
            let webp = try image(sharkWebP)

            #expect(jpeg.isPerceptuallySimilar(to: heic))
            #expect(jpeg.isPerceptuallySimilar(to: webp))
            #expect(heic.isPerceptuallySimilar(to: webp))
        }

        /// **The same picture at different sizes**, which is what taggers and rippers produce.
        /// Measured distances are 1-3 across a 16x range.
        @Test func rescalingDoesNotChangeThePicture() throws {
            let original = try image(sharkJPEG)

            for side in [512, 300, 128, 64, 32] {
                let scaled = try #require(original.scaled(to: CGSize(width: side, height: side)))
                #expect(
                    original.isPerceptuallySimilar(to: scaled),
                    "\(side)px copy was treated as a different picture"
                )
            }
        }

        /// Pins what `fingerprint` cannot do, so the two are never confused for one another. This is
        /// not a defect in `fingerprint` -- byte identity is the right question for the image store,
        /// and the wrong one for grouping artwork.
        @Test func fingerprintCannotAnswerThisQuestion() throws {
            let original = try image(sharkJPEG)
            let heic = try image(sharkHEIC)
            let scaled = try #require(original.scaled(to: CGSize(width: 300, height: 300)))

            #expect(original.fingerprint != heic.fingerprint)
            #expect(original.fingerprint != scaled.fingerprint)

            // Which the perceptual hash gets right.
            #expect(original.isPerceptuallySimilar(to: heic))
            #expect(original.isPerceptuallySimilar(to: scaled))
        }

        // MARK: - Discrimination

        /// Different pictures stay different, at any size -- the half of the job that a
        /// too-permissive tolerance would break, merging unrelated covers into one tile.
        @Test func differentPicturesAreNotSimilar() throws {
            let shark = try image(sharkJPEG)
            let other = try image(songbird)

            #expect(shark.isPerceptuallySimilar(to: other) == false)

            for side in [512, 128] {
                let scaled = try #require(other.scaled(to: CGSize(width: side, height: side)))
                #expect(shark.isPerceptuallySimilar(to: scaled) == false)
            }
        }

        /// **The tolerance sits in a gap, not on a boundary.** Same-picture distances measured 0-3
        /// and different-picture distances 34-36, so there is an order of magnitude of headroom on
        /// both sides. If this ever fails, the hash has changed character and the tolerance needs
        /// re-measuring rather than nudging.
        @Test func sameAndDifferentAreSeparatedByAWideMargin() throws {
            let shark = try image(sharkJPEG)
            let heic = try image(sharkHEIC)
            let other = try image(songbird)

            let same = try #require(shark.perceptualDistance(to: heic))
            let different = try #require(shark.perceptualDistance(to: other))

            #expect(same < CGImage.perceptualTolerance / 2, "same-picture distance was \(same)")
            #expect(different > CGImage.perceptualTolerance * 2, "different-picture distance was \(different)")
        }

        // MARK: - Properties

        @Test func hashingIsStableAcrossLoads() throws {
            #expect(try image(sharkJPEG).perceptualHash == (try image(sharkJPEG).perceptualHash))
        }

        @Test func anImageIsSimilarToItself() throws {
            let shark = try image(sharkJPEG)

            #expect(shark.perceptualDistance(to: shark) == 0)
            #expect(shark.isPerceptuallySimilar(to: shark))
        }

        /// Symmetric, so grouping does not depend on which image happens to be seen first.
        @Test func similarityIsSymmetric() throws {
            let jpeg = try image(sharkJPEG)
            let heic = try image(sharkHEIC)

            #expect(jpeg.perceptualDistance(to: heic) == heic.perceptualDistance(to: jpeg))
            #expect(jpeg.isPerceptuallySimilar(to: heic) == heic.isPerceptuallySimilar(to: jpeg))
        }

        /// A tolerance of zero demands an identical grid, which re-encoding does not guarantee --
        /// the reason the API compares with a distance rather than `==`.
        @Test func zeroToleranceIsStricterThanTheDefault() throws {
            let jpeg = try image(sharkJPEG)
            let heic = try image(sharkHEIC)

            #expect(jpeg.isPerceptuallySimilar(to: heic))
            #expect(jpeg.isPerceptuallySimilar(to: heic, tolerance: 0) == false)
        }
    }
#endif
