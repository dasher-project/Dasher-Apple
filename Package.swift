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
        .package(url: "https://github.com/JakubMazur/lucide-icons-swift", from: "1.20.0"),
        .package(url: "https://github.com/PostHog/posthog-ios", from: "3.0.0"),
    ],
    targets: [
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
                .product(name: "SwiftTTSWrapper", package: "swift-tts-wrapper"),
            ],
            path: "DasherSpeech"
        ),
    ]
)
