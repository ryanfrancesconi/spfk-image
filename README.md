# SPFKImage

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-image)](https://github.com/ryanfrancesconi/spfk-image/tags)
[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-image%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-image)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-image%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-image)

Image decoding, thumbnails, non-destructive adjustment, orientation edits, comparison and format
conversion over Core Image and ImageIO.

## Features

- Decode, scale and export `CGImage`, and downscaled thumbnails of still images, including SVG and
  PDF-compatible Illustrator files, which ImageIO cannot read
- Non-destructive photo adjustments stored as one Codable value (`ImageAdjustmentDescription`) and
  rendered by `ImageAdjustmentRenderer`, in sections that can each be bypassed:
  - Light: exposure, brilliance, highlights, shadows, brightness, contrast, black and white point
  - Color: saturation, vibrance, temperature, tint and sepia
  - Levels and RGB and per-channel Curves, with a histogram to draw them over
  - Selective Color across six hue bands, Black & White mixed from the same six bands, and Color
    Grading of shadows, midtones and highlights
  - Detail (sharpness, definition, noise reduction), Vignette and Grain
  - White balance from an image's near-gray pixels or a sampled point, and Auto Adjust, which
    balances white and then takes vibrance, highlights, shadows and Levels from Core Image's
    automatic enhancement
  - Wide-gamut and HDR color, and transparency, kept through the chain
- Rotation and flip as a pending edit, written into a file's orientation tag or rendered upright
- A byte fingerprint for exact matches, and a perceptual hash for images that look the same across
  re-encoding and resizing
- Format conversion to a new file (`ImageFormatConverter`), keeping gain maps and a chosen share of
  the source's metadata. It writes the types ImageIO can write, plus any type an `ImageFileEncoder`
  is supplied for, such as [spfk-webp](https://github.com/ryanfrancesconi/spfk-webp) and
  [spfk-jxl](https://github.com/ryanfrancesconi/spfk-jxl).

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
