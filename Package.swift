// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Darkness",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "Darkness",
            targets: ["Darkness"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "Darkness"
        ),
        .testTarget(
            name: "DarknessTests",
            dependencies: ["Darkness"]
        ),
    ]
)
