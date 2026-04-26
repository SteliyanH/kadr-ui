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
    targets: [
        .target(
            name: "KadrUI",
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
