// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lumen",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lumen", targets: ["Lumen"])
    ],
    targets: [
        .target(
            name: "LumenCore",
            path: "Sources/LumenCore"
        ),
        .executableTarget(
            name: "Lumen",
            dependencies: ["LumenCore"],
            path: "Sources/Lumen",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "LumenCoreTests",
            dependencies: ["LumenCore"],
            path: "Tests/LumenCoreTests",
            swiftSettings: [
                .unsafeFlags(["-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"])
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
