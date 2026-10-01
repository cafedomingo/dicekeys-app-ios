// swift-tools-version: 6.2
//
// Derivation: recipes and the passwords, secrets and keys derived from a DiceKey seed.
//
//   Derivation   recipe parsing and validation, the derived value types, and the engine
//                that does the hashing (the vendored C++ in SeededCrypto for now)
//   KeyFormats   OpenSSH, OpenPGP and BIP39 encodings of derived values

import PackageDescription

let package = Package(
    name: "Derivation",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "Derivation", targets: ["Derivation"]),
        .library(name: "KeyFormats", targets: ["KeyFormats"]),
    ],
    dependencies: [
        .package(path: "../SeededCrypto"),
    ],
    targets: [
        .target(
            name: "Derivation",
            dependencies: [.product(name: "SeededCrypto", package: "SeededCrypto")]
        ),
        .target(
            name: "KeyFormats",
            dependencies: ["Derivation", .product(name: "SeededCrypto", package: "SeededCrypto")]
        ),
        .testTarget(
            name: "DerivationTests",
            dependencies: ["Derivation", "KeyFormats"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
