// swift-tools-version: 6.2
//
// Derivation: recipes and the passwords, secrets and keys derived from a DiceKey seed.
//
//   Derivation   recipe parsing and validation, the derived value types, and the engine
//                that does the hashing and the key derivation
//   BLAKE2       the hash the derivation is built on
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
    targets: [
        .target(name: "BLAKE2"),
        .target(
            name: "Derivation",
            dependencies: ["BLAKE2"]
        ),
        .target(
            name: "KeyFormats",
            dependencies: ["Derivation"]
        ),
        .testTarget(
            name: "DerivationTests",
            dependencies: ["Derivation", "KeyFormats"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "BLAKE2Tests",
            dependencies: ["BLAKE2"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
