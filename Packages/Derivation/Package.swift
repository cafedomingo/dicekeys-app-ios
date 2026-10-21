// swift-tools-version: 6.3
//
// Derivation: recipes and the passwords, secrets and keys derived from a DiceKey seed.
//
//   Derivation   recipes (`KeyKind`, `KeyRecipe`) and their canonical JSON, the derived
//                value types, the DiceKey id, and the engine that does the hashing and
//                the key derivation
//   KeyFormats   OpenSSH, WireGuard, age and BIP39 encodings of derived values, and
//                `DerivedKey`, which derives and encodes each kind

import PackageDescription

let package = Package(
    name: "Derivation",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "Derivation", targets: ["Derivation"]),
        .library(name: "KeyFormats", targets: ["KeyFormats"])
    ],
    targets: [
        .target(name: "Derivation"),
        .target(
            name: "KeyFormats",
            dependencies: ["Derivation"]
        ),
        .testTarget(
            name: "DerivationTests",
            dependencies: ["Derivation", "KeyFormats"],
            resources: [.copy("Fixtures")]
        )
    ]
)
