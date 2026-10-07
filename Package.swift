// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Tracket",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Tracket", targets: ["Tracket"]),
        .executable(name: "tracket-hook", targets: ["TracketHook"]),
        .executable(name: "tracket-local-ai", targets: ["TracketLocalAI"])
    ],
    dependencies: [
        // 3.32.x currently requires the unreleased Swift 6.3 toolchain. Keep
        // this compatible release pinned until Xcode ships that compiler.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.31.4"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "Tracket",
            dependencies: [
                .product(name: "HuggingFace", package: "swift-huggingface")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AuthenticationServices"),
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("Network"),
                .linkedFramework("Security"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .executableTarget(name: "TracketHook"),
        .executableTarget(
            name: "TracketLocalAI",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ]
        ),
        .testTarget(
            name: "TracketTests",
            dependencies: ["Tracket"]
        )
    ],
    swiftLanguageModes: [.v5]
)
