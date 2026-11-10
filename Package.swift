// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WTaskbar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "WTaskbar", path: "Sources/WTaskbar")
    ]
)
