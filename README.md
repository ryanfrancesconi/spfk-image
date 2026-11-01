# SPFKImage

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-image)](https://github.com/ryanfrancesconi/spfk-image/tags)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-image%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-image)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-image%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-image)

Pixel-level image work over Core Image and ImageIO: decoding, encoding, resizing, adjusting and
comparing images, and converting a file to another format. It is a capability the products embed for
anything that turns pixels into bytes, and it holds no metadata model and no UI, so it can be
depended on without taking either on.

Two kinds of identity live here, for two questions. A byte fingerprint answers whether a store has
already written this exact image; a perceptual hash answers whether two files are the same picture
across re-encoding and resizing.

Conversion writes a new file and never replaces its input. It writes what ImageIO can, plus any type
an `ImageFileEncoder` is supplied for: [spfk-webp](https://github.com/ryanfrancesconi/spfk-webp) and
[spfk-jxl](https://github.com/ryanfrancesconi/spfk-jxl) add the formats ImageIO only reads.

XMP and descriptive metadata belong to spfk-metadata-image, video frames to spfk-video, and anything
on screen to the UI packages.

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
