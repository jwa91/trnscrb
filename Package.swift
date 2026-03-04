// swift-tools-version: 6.0

import PackageDescription

let package: Package = Package(
    name: "trnscrb",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "trnscrb",
            path: "trnscrb",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "TrnscrbrTests",
            dependencies: ["trnscrb"],
            path: "Tests"
        ),
    ]
)
