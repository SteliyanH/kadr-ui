// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KadrUI",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "KadrUI", targets: ["KadrUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SteliyanH/kadr.git", from: "0.8.4"),
    ],
    targets: [
        .target(
            name: "KadrUI",
            dependencies: [
                .product(name: "Kadr", package: "kadr"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "KadrUITests",
            dependencies: ["KadrUI"]
        ),
    ]
)
