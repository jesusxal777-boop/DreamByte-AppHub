// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DreamByteAppHubCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AppHubCore", targets: ["AppHubCore"])
    ],
    targets: [
        .target(
            name: "CZlib",
            path: "Sources/CZlib",
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("z")]
        ),
        .target(
            name: "AppHubCore",
            dependencies: ["CZlib"],
            path: "Sources/AppHubCore",
            resources: [.copy("Resources/Localization")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AppHubCoreTests",
            dependencies: ["AppHubCore"],
            path: "Tests/AppHubCoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
