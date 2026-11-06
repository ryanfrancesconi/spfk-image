# SPFKImage

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-image)](https://github.com/ryanfrancesconi/spfk-image/tags)
[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-image%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-image)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-image%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-image)

Image decoding, encoding, resizing, color adjustment, comparison and format conversion over Core
Image and ImageIO.

## Features

- Decode, scale and export `CGImage`
- Color adjustments: exposure, contrast, highlights, shadows, saturation, temperature, tint and more
  (`ImageAdjustmentDescription`, `ImageAdjustmentRenderer`)
- A byte fingerprint for exact matches, and a perceptual hash for images that look the same across
  re-encoding and resizing
- Format conversion to a new file (`ImageFormatConverter`). It writes the types ImageIO can write,
  plus any type an `ImageFileEncoder` is supplied for, such as
  [spfk-webp](https://github.com/ryanfrancesconi/spfk-webp) and
  [spfk-jxl](https://github.com/ryanfrancesconi/spfk-jxl).

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
