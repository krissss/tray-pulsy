// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "TrayPulsy",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "TrayPulsy", targets: ["TrayPulsy"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/Defaults", from: "9.0.0"),
        .package(url: "https://github.com/spacenation/swiftui-sliders", from: "2.1.0"),
        // TODO: KeyboardShortcuts — 等 Xcode 构建集成后再加（当前 swift build 不支持其 Preview 宏插件）
        // .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "TrayPulsy",
            dependencies: [
                .product(name: "Defaults", package: "Defaults"),
                .product(name: "Sliders", package: "swiftui-sliders"),
            ],
            path: "Sources",
            resources: [
                .copy("Resources"),
            ],
            swiftSettings: [
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release)),
            ]
        ),
        .testTarget(
            name: "TrayPulsyTests",
            dependencies: [
                "TrayPulsy",
                .product(name: "Defaults", package: "Defaults"),
            ],
            path: "Tests"
        ),
    ]
)
