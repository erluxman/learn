// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Learn",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Learn",
            path: "Sources/Learn",
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ]
)
