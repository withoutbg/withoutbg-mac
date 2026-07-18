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
                .copy("Resources/wbgnet_oss.mlpackage"),
                .copy("Resources/wbgnet_oss.mlpackage.json"),
                .copy("Resources/product-links.json"),
            ]
        ),
    ]
)
