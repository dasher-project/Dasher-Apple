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
        .package(url: "https://github.com/AACTools/rust-tts-wrapper.git", exact: "1.9.0"),
        .package(url: "https://github.com/tsolomko/SWCompression.git", from: "4.9.1"),
        .package(url: "https://github.com/aactools/swift-tts-wrapper", from: "1.2.8"),
        .package(url: "https://github.com/JakubMazur/lucide-icons-swift", from: "1.20.0"),
        .package(url: "https://github.com/PostHog/posthog-ios", from: "3.0.0"),
    ],
    targets: [
        .systemLibrary(name: "CBZip2", path: "DasherSpeechSupport/CBZip2"),
        .target(
            name: "DasherShared",
            dependencies: [
                .product(name: "LucideIcons", package: "lucide-icons-swift"),
                .product(name: "PostHog", package: "posthog-ios"),
            ],
            path: "DasherShared"
        ),
        .target(
            name: "DasherSpeech",
            dependencies: [
                .target(name: "DasherShared"),
                .target(name: "CBZip2", condition: .when(platforms: [.macOS, .iOS])),
                .product(name: "SwiftTTSWrapper", package: "swift-tts-wrapper"),
                .product(name: "SWCompression", package: "SWCompression", condition: .when(platforms: [.macOS, .iOS])),
                .product(name: "RustTtsWrapper", package: "rust-tts-wrapper", condition: .when(platforms: [.macOS, .iOS])),
            ],
            path: "DasherSpeech"
        ),
        .testTarget(name: "DasherSpeechTests", dependencies: ["DasherSpeech"]),
        .testTarget(
            name: "DasherSharedTests",
            dependencies: [
                .target(name: "DasherShared"),
            ],
            path: "Tests/DasherSharedTests"
        ),
    ]
)
