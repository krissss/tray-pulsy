// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RunCatX",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "RunCatX", targets: ["RunCatX"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/Defaults", from: "9.0.0"),
        // TODO: KeyboardShortcuts — 等 Xcode 构建集成后再加（当前 swift build 不支持其 Preview 宏插件）
        // .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "RunCatX",
            dependencies: [
                .product(name: "Defaults", package: "Defaults"),
            ],
            path: "RunCatX",
            resources: [
                .copy("Resources/cat"),
                .copy("Resources/horse"),
                .copy("Resources/parrot"),
            ],
            swiftSettings: [
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release)),
            ]
        ),
    ]
)
