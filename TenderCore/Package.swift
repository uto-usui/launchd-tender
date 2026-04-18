// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TenderCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "TenderCore",
            targets: ["TenderCore"]
        )
    ],
    targets: [
        .target(
            name: "TenderCore",
            path: "Sources/TenderCore"
        ),
        .testTarget(
            name: "TenderCoreTests",
            dependencies: ["TenderCore"],
            path: "Tests/TenderCoreTests"
        )
    ]
)
