// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AscensionNotes",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .executable(
            name: "AscensionNotesApp",
            targets: ["AscensionNotesApp"]
        ),
        .library(
            name: "AscensionCore",
            targets: ["AscensionCore"]
        )
    ],
    targets: [
        .target(
            name: "AscensionCore"
        ),
        .executableTarget(
            name: "AscensionNotesApp",
            dependencies: ["AscensionCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "AscensionCoreTests",
            dependencies: ["AscensionCore"]
        )
    ]
)
