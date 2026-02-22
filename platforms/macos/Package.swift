// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenLens",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ScreenLens",
            dependencies: [],
            path: "ScreenLens/Sources",
            linkerSettings: [
                // Link against the Rust FFI library
                .unsafeFlags(["-L../../target/release"]),
                .linkedLibrary("screenlens_ffi"),
            ]
        ),
    ]
)
