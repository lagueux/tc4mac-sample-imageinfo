// swift-tools-version: 6.2
import PackageDescription

// The logic is a library and the plugin process is a thin executable over it.
// That keeps the interesting part testable — an executable target cannot be
// imported by tests without colliding on `main`.
let package = Package(
    name: "ImageInfoPlugin",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/lagueux/tc4mac-plugin-sdk.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "ImageInfoKit",
            dependencies: [.product(name: "TCPluginSDK", package: "tc4mac-plugin-sdk")]),
        .executableTarget(name: "ImageInfoPlugin", dependencies: ["ImageInfoKit"]),
        .testTarget(name: "ImageInfoPluginTests", dependencies: ["ImageInfoKit"])
    ]
)
