// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "BuildTools",
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.65.1"),
        .package(url: "https://github.com/yonaskolb/XcodeGen", exact: "2.46.0"),
    ],
    targets: []
)
