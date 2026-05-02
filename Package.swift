// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TrayPulsy",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "TrayPulsy", targets: ["TrayPulsy"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/Defaults", from: "9.0.0"),
        .package(url: "https://github.com/spacenation/swiftui-sliders", from: "2.1.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "TrayPulsy",
            dependencies: [
                .product(name: "Defaults", package: "Defaults"),
                .product(name: "Sliders", package: "swiftui-sliders"),
                .product(name: "Sparkle", package: "Sparkle"),
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
