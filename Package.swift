// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DonCSV",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "DonCSV", targets: ["DonCSV"])
    ],
    targets: [
        .executableTarget(
            name: "DonCSV",
            path: "Sources/DonCSV"
        )
    ]
)
