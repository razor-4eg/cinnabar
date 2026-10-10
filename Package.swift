// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cinnabar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Cinnabar", targets: ["Cinnabar"])
    ],
    targets: [
        .target(
            name: "CinnabarCore",
            path: "Sources/CinnabarCore"
        ),
        .executableTarget(
            name: "Cinnabar",
            dependencies: ["CinnabarCore"],
            path: "Sources/Cinnabar",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "CinnabarCoreTests",
            dependencies: ["CinnabarCore"],
            path: "Tests/CinnabarCoreTests",
            swiftSettings: [
                .unsafeFlags(["-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"])
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
