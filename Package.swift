// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Tracket",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Tracket", targets: ["Tracket"]),
        .executable(name: "tracket-hook", targets: ["TracketHook"])
    ],
    targets: [
        .executableTarget(
            name: "Tracket",
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
        .testTarget(
            name: "TracketTests",
            dependencies: ["Tracket"]
        )
    ],
    swiftLanguageModes: [.v5]
)
