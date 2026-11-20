// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NXLibrary",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "NXLibraryCore", targets: ["NXLibraryCore"]),
        .library(name: "ArcanePorting", targets: ["ArcanePorting"]),
        .executable(name: "NXLibrary", targets: ["NXLibrary"]),
    ],
    targets: [
        .target(name: "NXLibraryCore", path: "Sources/NXLibraryCore", resources: [.process("Resources")]),
        .target(name: "ArcanePorting", dependencies: ["NXLibraryCore"], path: "Sources/ArcanePorting"),
        .executableTarget(
            name: "NXLibrary",
            dependencies: ["NXLibraryCore", "ArcanePorting"],
            path: "Sources/NXLibrary"
        ),
        .testTarget(
            name: "NXLibraryCoreTests",
            dependencies: ["NXLibraryCore", "ArcanePorting"],
            path: "Tests/NXLibraryCoreTests"
        ),
    ]
)
