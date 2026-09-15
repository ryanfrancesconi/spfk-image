# SPFKImage

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-image)](https://github.com/ryanfrancesconi/spfk-image/tags)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-image%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-image)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-image%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-image)

Pixel-level image work for Swift, over Core Image and ImageIO: encoding, decoding, resizing and
hashing `CGImage`. It holds no metadata model and no UI, so anything that needs to turn pixels into
bytes or compare two images can depend on it without taking on more.

## Features

- **Adjusting** — `ImageAdjustmentDescription` is a color adjustment stored as slider positions, and
  `ImageAdjustmentRenderer` applies it through Core Image: `render(_:source:)` for a preview bitmap,
  and `renderFile(_:source:destination:quality:)` to write a new file in the source's format that
  keeps its metadata, orientation and auxiliary images (gain maps, depth, mattes).
- **Converting** — `ImageFormatConverter` writes one file into another format, keeping, dropping the
  location from, or stripping its metadata, and never replacing its input. `ImageConversionFormats` lists
  what it can write: ImageIO's types, plus any `ImageFileEncoder` supplied for a type ImageIO only reads
  ([spfk-webp](https://github.com/ryanfrancesconi/spfk-webp), [spfk-jxl](https://github.com/ryanfrancesconi/spfk-jxl)).
- **Encoding** — `export(utType:to:)` writes PNG, JPEG, HEIF or TIFF through `CIContext`, and
  `dataRepresentation(utType:dpi:compression:excludeGPSData:otherOptions:)` returns encoded data
  through ImageIO. Neither carries the source file's metadata: they encode a bare image.
- **Decoding** — `CGImage.create(from:)` and `CGImage.contentsOf(url:)` decode the first image of a
  file or data blob.
- **Resizing** — `scaled(to:)` redraws at a target size with high-quality interpolation.
- **Byte identity** — `fingerprint` hashes geometry plus the whole pixel buffer, and
  `hasEqualPixelData(_:)` compares buffers directly. The right question for a store deduplicating
  what it has already written.
- **Perceptual identity** — `perceptualHash` is a 64-bit difference hash, compared with
  `perceptualDistance(to:)` or `isPerceptuallySimilar(to:tolerance:)`. The right question for "is
  this the same picture", across re-encoding and resizing.

## Dependencies

| Package | Description |
|---------|-------------|
| [spfk-base](https://github.com/ryanfrancesconi/spfk-base) | Core utilities and extensions |

## Requirements

- **Platforms:** macOS 13+, iOS 16+
- **Swift:** 6.2+

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
