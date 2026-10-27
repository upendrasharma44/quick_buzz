// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuzzNetwork",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "BuzzNetwork", targets: ["BuzzNetwork"]),
    ],
    dependencies: [
        .package(path: "../BuzzCore"),
    ],
    targets: [
        .target(
            name: "BuzzNetwork",
            dependencies: ["BuzzCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BuzzNetworkTests",
            dependencies: ["BuzzNetwork"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
