// swift-tools-version: 6.2
//
// Pins the command-line tools the project uses, so CI and local builds run the same versions
// and Dependabot can bump them. It has no targets of its own.
//
//   swift run --package-path BuildTools xcodegen generate
//
// SwiftLint is a prebuilt binary target, which `swift run` cannot start. After
// `swift package --package-path BuildTools resolve` it is at
// BuildTools/.build/artifacts/swiftlintplugins/SwiftLintBinary/SwiftLintBinary.artifactbundle/macos/swiftlint.

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
