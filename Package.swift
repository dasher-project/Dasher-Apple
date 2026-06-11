// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dasher",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DasherShared", targets: ["DasherShared"]),
    ],
    dependencies: [
        .package(url: "https://github.com/aactools/swift-tts-wrapper", from: "1.2.4"),
    ],
    targets: [
        .target(
            name: "DasherShared",
            dependencies: [
                .product(name: "SwiftTTSWrapper", package: "swift-tts-wrapper"),
            ],
            path: "DasherShared"
        ),
    ]
)
