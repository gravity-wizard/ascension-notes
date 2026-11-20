// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AscensionNotes",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "AscensionCore",
            targets: ["AscensionCore"]
        ),
        .executable(
            name: "AscensionNotesApp",
            targets: ["AscensionNotesApp"]
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
