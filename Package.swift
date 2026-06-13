// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dasher",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DasherShared", targets: ["DasherShared"]),
        .library(name: "DasherSpeech", targets: ["DasherSpeech"]),
    ],
    dependencies: [
        .package(url: "https://github.com/aactools/swift-tts-wrapper", from: "1.2.5"),
    ],
    targets: [
        .target(
            name: "DasherShared",
            dependencies: [],
            path: "DasherShared"
        ),
        .target(
            name: "DasherSpeech",
            dependencies: [
                .target(name: "DasherShared"),
                .product(name: "SwiftTTSWrapper", package: "swift-tts-wrapper"),
            ],
            path: "DasherSpeech"
        ),
    ]
)
