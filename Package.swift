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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(
            name: "VellumCore",
            path: "Sources/VellumCore"
        ),
        .executableTarget(
            name: "Vellum",
            dependencies: ["VellumCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Vellum",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "VellumTests",
            dependencies: ["VellumCore"],
            path: "Tests/VellumTests"
        ),
        .testTarget(
            name: "VellumAppTests",
            dependencies: ["Vellum", "VellumCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Tests/VellumAppTests"
        )
    ]
)
