// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PresenceFM",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "PresenceFM", targets: ["PresenceFM"])],
    targets: [
        .executableTarget(
            name: "PresenceFM",
            path: "Sources/PresenceFM",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PresenceFMTests",
            dependencies: ["PresenceFM"],
            path: "Tests/PresenceFMTests"
        )
    ]
)
