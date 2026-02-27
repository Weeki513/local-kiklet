// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LocalKiklet",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "LocalKiklet", targets: ["LocalKiklet"])
    ],
    targets: [
        .executableTarget(
            name: "LocalKiklet",
            resources: [.process("Resources")]
        )
    ]
)
