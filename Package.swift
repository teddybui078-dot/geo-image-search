// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GeoImageSearch",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "GeoImageSearch",
            path: "Sources/GeoImageSearch"
        ),
        .testTarget(
            name: "GeoImageSearchTests",
            dependencies: ["GeoImageSearch"],
            path: "Tests/GeoImageSearchTests"
        )
    ]
)
