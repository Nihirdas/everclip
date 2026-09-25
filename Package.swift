// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EverClip",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "EverClipCore", targets: ["EverClipCore"]),
        .executable(name: "EverClip", targets: ["EverClip"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        // Platform-independent core: model, storage, search, retention, export.
        // Kept free of AppKit so a future Windows port can reuse it (see ROADMAP).
        .target(
            name: "EverClipCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        // macOS menu-bar application.
        .executableTarget(
            name: "EverClip",
            dependencies: ["EverClipCore"]
        ),
        .testTarget(
            name: "EverClipCoreTests",
            dependencies: ["EverClipCore"]
        )
    ]
)
