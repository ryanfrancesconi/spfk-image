// swift-tools-version: 6.2
// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import PackageDescription

let package = Package(
    name: "spfk-image",
    platforms: [.macOS(.v13), .iOS(.v16),],
    products: [
        .library(
            name: "SPFKImage",
            targets: ["SPFKImage",]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ryanfrancesconi/spfk-base", from: "1.10.0"),
    ],
    targets: [
        .target(
            name: "SPFKImage",
            dependencies: [
                .product(name: "SPFKBase", package: "spfk-base"),
            ]
        ),
    ]
)
