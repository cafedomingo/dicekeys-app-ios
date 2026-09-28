// swift-tools-version: 6.2
//
// Tool pins for CI and local use, bumped by Dependabot.
//   swift run --package-path BuildTools xcodegen generate

import PackageDescription

let package = Package(
    name: "BuildTools",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.65.1"),
        .package(url: "https://github.com/yonaskolb/XcodeGen", exact: "2.46.0"),
    ],
    targets: []
)
