// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CornixBattery",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CornixBattery",
            path: "Sources"
        )
    ]
)
