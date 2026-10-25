// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuzzCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "BuzzCore", targets: ["BuzzCore"]),
    ],
    targets: [
        .target(
            name: "BuzzCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BuzzCoreTests",
            dependencies: ["BuzzCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
