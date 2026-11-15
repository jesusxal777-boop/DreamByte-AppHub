// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DreamByteAppHub",
    defaultLocalization: "es",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .executable(name: "DreamByteAppHub", targets: ["DreamByteAppHub"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .executableTarget(
            name: "DreamByteAppHub",
            dependencies: [
                .product(name: "AppHubCore", package: "Core")
            ],
            path: "Sources/DreamByteAppHub",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
