// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BodianLyrics",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BodianCore"),
        .executableTarget(name: "BodianLyrics", dependencies: ["BodianCore"]),
        .executableTarget(name: "BodianEngine", dependencies: ["BodianCore"])
    ]
)
