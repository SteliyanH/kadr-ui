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
        .package(url: "https://github.com/SteliyanH/kadr.git", from: "0.11.0"),
        // v0.10.1 — visual-regression baselines on the editor views. Test-
        // only; main library has no third-party deps.
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.0"),
        // v0.10.1 — modifier-tree inspection for gesture wiring tests
        // (verifies the right .gesture / .onTapGesture / .simultaneousGesture
        // modifiers are attached, even where the gesture can't be fired
        // programmatically).
        .package(url: "https://github.com/nalexn/ViewInspector", from: "0.10.0"),
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
            dependencies: [
                "KadrUI",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "ViewInspector", package: "ViewInspector"),
            ]
        ),
    ]
)
