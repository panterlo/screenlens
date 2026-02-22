// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenLens",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ScreenLens",
            dependencies: [
                "TOMLKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "ScreenLens/Sources"
        ),
    ]
)
