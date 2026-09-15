// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Phantom",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Phantom",
            path: "Sources/Phantom",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
