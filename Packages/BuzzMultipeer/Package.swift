// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuzzMultipeer",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "BuzzMultipeer", targets: ["BuzzMultipeer"]),
    ],
    dependencies: [
        .package(path: "../BuzzCore"),
    ],
    targets: [
        .target(
            name: "BuzzMultipeer",
            dependencies: ["BuzzCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BuzzMultipeerTests",
            dependencies: ["BuzzMultipeer"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
