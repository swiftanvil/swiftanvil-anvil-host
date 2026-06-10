// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "swiftanvil-anvil-host",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AnvilHost", targets: ["AnvilHost"]),
        .executable(name: "anvil-host", targets: ["AnvilHostCLI"])
    ],
    dependencies: [
        .package(path: "../swiftanvil-anvil-runner")
    ],
    targets: [
        .target(
            name: "AnvilHost",
            dependencies: [
                .product(name: "AnvilRunner", package: "swiftanvil-anvil-runner")
            ]
        ),
        .executableTarget(
            name: "AnvilHostCLI",
            dependencies: ["AnvilHost"]
        )
    ]
)
