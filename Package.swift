// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GeoImageSearch",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Vendored SQLite amalgamation (sqlite.org), not the system libsqlite3.
        // See Sources/CSQLite3/VENDORED.md for why: Apple's system SQLite
        // disables sqlite3_auto_extension, which breaks static sqlite-vec
        // registration (see CSQLiteVec below).
        .target(
            name: "CSQLite3",
            path: "Sources/CSQLite3",
            exclude: ["VENDORED.md"],
            cSettings: [
                .define("SQLITE_CORE", to: "1"),
                .define("SQLITE_ENABLE_RTREE", to: "1")
            ]
        ),
        // Vendored sqlite-vec amalgamation (asg017/sqlite-vec v0.1.9), compiled
        // SQLITE_CORE-mode against CSQLite3 so sqlite3_vec_init can be called
        // directly on a connection with no extension-loading machinery.
        .target(
            name: "CSQLiteVec",
            dependencies: ["CSQLite3"],
            path: "Sources/CSQLiteVec",
            exclude: ["VENDORED.md"],
            cSettings: [
                .define("SQLITE_CORE", to: "1")
            ]
        ),
        .executableTarget(
            name: "GeoImageSearch",
            dependencies: ["CSQLite3", "CSQLiteVec"],
            path: "Sources/GeoImageSearch",
            // The OpenGlobus HTML/JS/vendor bundle the globe WKWebView
            // loads via Bundle.module — .copy (not .process) since these
            // are pre-built files, not assets SPM should optimize/rewrite.
            resources: [
                .copy("Globe/Resources")
            ]
        ),
        .testTarget(
            name: "GeoImageSearchTests",
            dependencies: ["GeoImageSearch", "CSQLite3", "CSQLiteVec"],
            path: "Tests/GeoImageSearchTests"
        )
    ]
)
