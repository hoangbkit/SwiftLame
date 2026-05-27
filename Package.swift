// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftLame",
    platforms: [.macOS(.v15)],
    products: [
        .library(
            name: "SwiftLame",
            targets: ["SwiftLame"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "lame",
            path: "Frameworks/lame.xcframework"
        ),
        .target(
            name: "SwiftLame",
            dependencies: ["lame"],
            path: "Sources/SwiftLame"
        ),
        .testTarget(
            name: "SwiftLameTests",
            dependencies: ["SwiftLame"],
            path: "Tests/SwiftLameTests",
            resources: [
                .copy("InputAudios")
            ]
        ),
    ]
)
