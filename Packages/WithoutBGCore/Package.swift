// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WithoutBGCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "WithoutBGCore",
            targets: ["WithoutBGCore"]
        ),
    ],
    targets: [
        .target(
            name: "WithoutBGCore",
            path: "Sources/WithoutBGCore",
            resources: [
                .copy("Resources/product-links.json"),
                .copy("Resources/withoutbg-open-weights.coreml.json"),
                .copy("Resources/withoutbg-open-weights-backbone.mlpackage"),
                .copy("Resources/withoutbg-open-weights.mlpackage"),
                .copy("Resources/birefnet-general.mlpackage"),
            ]
        ),
        .testTarget(
            name: "WithoutBGCoreTests",
            dependencies: ["WithoutBGCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
