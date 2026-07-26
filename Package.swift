// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LiveWall",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4")
    ],
    targets: [
        .executableTarget(
            name: "LiveWall",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/LiveWall"
        )
    ]
)
