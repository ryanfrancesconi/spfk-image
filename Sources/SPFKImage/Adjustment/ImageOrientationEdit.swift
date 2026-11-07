// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import CoreImage
import Foundation
import ImageIO

/// A pending rotation or mirror, applied on top of what a file displays now. One of the 8 symmetries of
/// the square, each with the EXIF orientation value that performs it.
///
/// `.up` is no edit. A file's new orientation tag is ``applied(toFileOrientation:)``.
public enum ImageOrientationEdit: Int, Codable, Sendable, Hashable, CaseIterable {
    case up = 1
    case upMirrored = 2
    case down = 3
    case downMirrored = 4
    case leftMirrored = 5
    case right = 6
    case rightMirrored = 7
    case left = 8

    /// A user command, acting on the image as it is displayed.
    public enum Command: Sendable, Hashable, CaseIterable {
        case rotateLeft
        case rotateRight
        case flipHorizontal
        case flipVertical

        /// The edit that performs this command on its own.
        public var edit: ImageOrientationEdit {
            switch self {
            case .rotateLeft: .left
            case .rotateRight: .right
            case .flipHorizontal: .upMirrored
            case .flipVertical: .downMirrored
            }
        }
    }

    public var isIdentity: Bool { self == .up }

    /// Whether the displayed width and height trade places.
    public var swapsDimensions: Bool { quarterTurns % 2 == 1 }

    /// `command` performed after this edit, in display space.
    public func applying(_ command: Command) -> ImageOrientationEdit {
        command.edit.composed(after: self)
    }

    public var rotatedLeft: ImageOrientationEdit { applying(.rotateLeft) }
    public var rotatedRight: ImageOrientationEdit { applying(.rotateRight) }
    public var flippedHorizontally: ImageOrientationEdit { applying(.flipHorizontal) }
    public var flippedVertically: ImageOrientationEdit { applying(.flipVertical) }

    /// The orientation tag that displays a file tagged `fileOrientation` with this edit performed.
    /// An out-of-range tag reads as 1, as ImageIO treats it.
    public func applied(toFileOrientation fileOrientation: Int) -> Int {
        composed(after: ImageOrientationEdit(rawValue: fileOrientation) ?? .up).rawValue
    }

    /// `image` with this edit performed, its extent moved back to the origin.
    public func apply(to image: CIImage) -> CIImage {
        guard !isIdentity else { return image }

        let oriented = image.oriented(cgImagePropertyOrientation)

        return oriented.transformed(by: CGAffineTransform(translationX: -oriented.extent.minX, y: -oriented.extent.minY))
    }

    public var cgImagePropertyOrientation: CGImagePropertyOrientation {
        CGImagePropertyOrientation(rawValue: UInt32(rawValue)) ?? .up
    }

    // MARK: - Composition

    /// Each value as clockwise quarter turns applied after an optional left-right mirror.
    private var quarterTurns: Int {
        switch self {
        case .up, .upMirrored: 0
        case .right, .rightMirrored: 1
        case .down, .downMirrored: 2
        case .left, .leftMirrored: 3
        }
    }

    private var mirrored: Bool {
        switch self {
        case .upMirrored, .downMirrored, .leftMirrored, .rightMirrored: true
        default: false
        }
    }

    private init(quarterTurns: Int, mirrored: Bool) {
        let turns = ((quarterTurns % 4) + 4) % 4

        self = Self.allCases.first { $0.quarterTurns == turns && $0.mirrored == mirrored } ?? .up
    }

    /// This edit performed after `other`. A mirror reverses the direction of any turn performed before it.
    func composed(after other: ImageOrientationEdit) -> ImageOrientationEdit {
        ImageOrientationEdit(
            quarterTurns: quarterTurns + (mirrored ? -other.quarterTurns : other.quarterTurns),
            mirrored: mirrored != other.mirrored
        )
    }
}
