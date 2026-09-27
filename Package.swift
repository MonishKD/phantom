// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Phantom",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Phantom",
            path: "Sources/Phantom",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
