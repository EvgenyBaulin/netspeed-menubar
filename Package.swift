// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NetSpeedMenuBar",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "NetSpeedMenuBar",
            path: "Sources/NetSpeedMenuBar"
        )
    ]
)
