// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Bonk",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Bonk", targets: ["BonkApp"]),
        .library(name: "BonkCore", targets: ["BonkCore"])
    ],
    targets: [
        .target(
            name: "BonkCore",
            path: "Sources/BonkCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "BonkApp",
            dependencies: ["BonkCore"],
            path: "Sources/BonkApp"
        ),
        .executableTarget(
            name: "BonkChecks",
            dependencies: ["BonkCore"],
            path: "Checks"
        ),
        .executableTarget(
            name: "BonkCharacterGallery",
            dependencies: ["BonkCore"],
            path: "Tools/CharacterGallery"
        ),
        .testTarget(
            name: "BonkCoreTests",
            dependencies: ["BonkCore"],
            path: "Tests/BonkCoreTests"
        )
    ]
)
