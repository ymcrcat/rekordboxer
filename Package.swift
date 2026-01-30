// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Rekordboxer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "RekordboxerCore",
            path: "Sources/RekordboxerCore"
        ),
        .executableTarget(
            name: "Rekordboxer",
            dependencies: ["RekordboxerCore"],
            path: "Sources/Rekordboxer"
        ),
        .testTarget(
            name: "RekordboxerCoreTests",
            dependencies: ["RekordboxerCore"],
            path: "Tests/RekordboxerCoreTests"
        ),
    ]
)
