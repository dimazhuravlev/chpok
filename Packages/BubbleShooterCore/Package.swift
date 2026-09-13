// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BubbleShooterCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "BubbleShooterCore",
            targets: ["BubbleShooterCore"]
        )
    ],
    targets: [
        .target(
            name: "BubbleShooterCore"
        ),
        .testTarget(
            name: "BubbleShooterCoreTests",
            dependencies: ["BubbleShooterCore"]
        )
    ]
)
