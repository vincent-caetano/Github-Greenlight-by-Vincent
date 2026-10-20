// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Greenlight",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Greenlight", path: "Sources/Greenlight")
    ]
)
