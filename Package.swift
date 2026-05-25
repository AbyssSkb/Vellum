// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VimPDF",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VimPDF", targets: ["VimPDF"])
    ],
    targets: [
        .executableTarget(
            name: "VimPDF",
            path: "Sources/VimPDF"
        )
    ]
)
