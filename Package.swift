// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RunCatX",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "RunCatX", targets: ["RunCatX"]),
    ],
    targets: [
        .executableTarget(
            name: "RunCatX",
            path: "RunCatX",
            resources: [
                .copy("Resources/cat"),
            ],
            swiftSettings: [
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release)),
            ]
        ),
    ]
)
