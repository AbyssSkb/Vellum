// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Vellum",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Vellum", targets: ["Vellum"]),
        .library(name: "VellumCore", targets: ["VellumCore"])
    ],
    targets: [
        .target(
            name: "VellumCore",
            path: "Sources/VellumCore"
        ),
        .executableTarget(
            name: "Vellum",
            dependencies: ["VellumCore"],
            path: "Sources/Vellum"
        ),
        .testTarget(
            name: "VellumTests",
            dependencies: ["VellumCore"],
            path: "Tests/VellumTests"
        )
    ]
)
