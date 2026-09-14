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
        .package(url: "https://github.com/ryanfrancesconi/spfk-filesystem", from: "1.2.4"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-testing", from: "1.10.0"),
    ],
    targets: [
        .target(
            name: "SPFKImage",
            dependencies: [
                .product(name: "SPFKBase", package: "spfk-base"),
                .product(name: "SPFKFileSystem", package: "spfk-filesystem"),
            ]
        ),
        .testTarget(
            name: "SPFKImageTests",
            dependencies: [
                .targetItem(name: "SPFKImage", condition: nil),
                .product(name: "SPFKFileSystem", package: "spfk-filesystem"),
                .product(name: "SPFKTesting", package: "spfk-testing"),
            ]
        ),
    ]
)
