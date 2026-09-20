// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Backspacer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Backspacer",
            path: "Sources/Backspacer"
        ),
        .testTarget(
            name: "BackspacerTests",
            dependencies: ["Backspacer"],
            path: "Tests/BackspacerTests"
        )
    ]
)
