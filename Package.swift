// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Vellum",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Vellum", targets: ["Vellum"])
    ],
    targets: [
        .executableTarget(
            name: "Vellum",
            path: "Sources/Vellum"
        ),
        .testTarget(
            name: "VellumTests",
            dependencies: ["Vellum"],
            path: "Tests/VellumTests"
        )
    ]
)
