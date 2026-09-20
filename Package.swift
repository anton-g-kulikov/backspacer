// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "Backspacer",
    platforms: [.macOS(.v13)],
    dependencies: [
        // In-app updates (ADR-21). Pinned by revision: the tag v2.10.0 as of 2026-09-20.
        .package(url: "https://github.com/sparkle-project/Sparkle", revision: "eef1a539a373c1f1a320624b1130fc5de7b2e100"),
    ],
    targets: [
        .executableTarget(
            name: "Backspacer",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Backspacer"
        ),
        .testTarget(
            name: "BackspacerTests",
            dependencies: ["Backspacer"],
            path: "Tests/BackspacerTests"
        )
    ]
)
