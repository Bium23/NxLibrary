// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NXLibrary",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "NXLibraryCore", targets: ["NXLibraryCore"]),
        .executable(name: "NXLibrary", targets: ["NXLibrary"]),
    ],
    targets: [
        .target(name: "NXLibraryCore", path: "Sources/NXLibraryCore"),
        .executableTarget(
            name: "NXLibrary",
            dependencies: ["NXLibraryCore"],
            path: "Sources/NXLibrary"
        ),
        .testTarget(
            name: "NXLibraryCoreTests",
            dependencies: ["NXLibraryCore"],
            path: "Tests/NXLibraryCoreTests"
        ),
    ]
)
