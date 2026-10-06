// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SweetNoSleep",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SweetNoSleep", targets: ["SweetNoSleep"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SweetNoSleep",
            path: "Sources/SweetNoSleep",
            resources: [
                .copy("../../Resources")
            ]
        )
    ]
)
