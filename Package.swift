// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Reclaimer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Reclaimer",
            path: "Sources/Reclaimer"
        ),
        .testTarget(
            name: "ReclaimerTests",
            dependencies: ["Reclaimer"],
            path: "Tests/ReclaimerTests"
        )
    ]
)
