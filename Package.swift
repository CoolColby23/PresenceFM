// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PresenceFM",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PresenceFMCore", targets: ["PresenceFMCore"]),
        .executable(name: "PresenceFM", targets: ["PresenceFM"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2")
    ],
    targets: [
        .target(name: "PresenceFMCore", path: "Sources/PresenceFMCore"),
        .executableTarget(
            name: "PresenceFM",
            dependencies: ["PresenceFMCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/PresenceFM",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PresenceFMCoreTests",
            dependencies: ["PresenceFMCore"],
            path: "Tests/PresenceFMCoreTests"
        ),
        .testTarget(
            name: "PresenceFMTests",
            dependencies: ["PresenceFM", "PresenceFMCore"],
            path: "Tests/PresenceFMTests",
            linkerSettings: [
                // SwiftPM does not add its binary-framework output directory to
                // test bundles that depend on an executable target.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../.."])
            ]
        ),
    ]
)
