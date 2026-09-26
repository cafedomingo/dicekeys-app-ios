// swift-tools-version: 6.2
//
// DiceKeysCore: the native libraries the DiceKeys app depends on, vendored as
// sources so the app builds with no CocoaPods, no submodules, no Objective-C, no
// third-party binaries and no network access beyond what Xcode itself needs.
//
//   CSodium            libsodium 1.0.22 compiled from source (C)
//   SeededCryptoCXX    DiceKeys lib-seeded (C++), a git subtree under Vendor/
//   SeededCryptoNative our C-ABI shim over it
//   SeededCrypto       Swift API used by the app
//   ReadDiceKey        the DiceKeys scanner, ported to pure Swift (Foundation only)
//
// Provenance: Sources/CSodium/VENDOR.md (libsodium copy) and the subtree commit history of
// Vendor/seeded-crypto (`git log -- Packages/DiceKeysCore/Vendor/seeded-crypto`).

import PackageDescription

let package = Package(
    name: "DiceKeysCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "SeededCrypto", targets: ["SeededCrypto"]),
        .library(name: "ReadDiceKey", targets: ["ReadDiceKey"]),
    ],
    targets: [
        // MARK: libsodium, compiled from source.
        // The defines mirror what libsodium's own configure script sets for Apple targets;
        // they were the same set the old CocoaPods spec used. Every .c file is compiled;
        // implementations that need x86 intrinsics compile to stubs on arm64.
        .target(
            name: "CSodium",
            path: "Sources/CSodium",
            exclude: ["LICENSE", "VENDOR.md"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include/sodium"),
                .define("CONFIGURED", to: "1"),
                .define("NATIVE_LITTLE_ENDIAN", to: "1"),
                .define("HAVE_MADVISE", to: "1"),
                .define("HAVE_MMAP", to: "1"),
                .define("HAVE_MPROTECT", to: "1"),
                .define("HAVE_POSIX_MEMALIGN", to: "1"),
                .define("HAVE_WEAK_SYMBOLS", to: "1"),
                .define("HAVE_TI_MODE", to: "1"),
                // Without HAVE_PTHREAD (or HAVE_ATOMIC_OPS) sodium_init() has no lock, so two
                // threads deriving for the first time both run _sodium_alloc_init(), the
                // guarded-memory canary is re-randomised under a live allocation, and the
                // next sodium_free() aborts. configure sets both on Apple platforms.
                .define("HAVE_PTHREAD", to: "1"),
                .define("HAVE_ATOMIC_OPS", to: "1"),
                .unsafeFlags(["-w"]),
            ]
        ),

        // MARK: DiceKeys seeded-crypto, a git subtree of dicekeys/seeded-crypto (unmodified
        // sources; see scripts/update-seeded-crypto.sh), with our C ABI on top.
        .target(
            name: "SeededCryptoCXX",
            dependencies: ["CSodium"],
            path: "Vendor/seeded-crypto/lib-seeded",
            exclude: ["CMakeLists.txt"],
            publicHeadersPath: ".",
            cxxSettings: [
                .unsafeFlags(["-Wno-everything"]),
            ]
        ),
        .target(
            name: "SeededCryptoNative",
            dependencies: ["SeededCryptoCXX", "CSodium"],
            path: "Sources/SeededCryptoNative",
            exclude: ["VENDOR.md"],
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(["-Wno-everything"]),
            ]
        ),
        .target(
            name: "SeededCrypto",
            dependencies: ["SeededCryptoNative"],
            path: "Sources/SeededCrypto"
        ),

        // MARK: DiceKeys scanner, pure Swift. Validated against upstream's photo corpus
        // and the C++ reference output in Tests/ReadDiceKeyTests.
        // Always optimized: at -Onone a 1080x1080 camera frame takes ~6 s to scan on an
        // M2 (49 ms at -O), so a Debug run of the app would be unusable and the corpus
        // tests take minutes. Unsafe flags are allowed here because the package is a
        // local path dependency.
        .target(
            name: "ReadDiceKey",
            dependencies: [],
            path: "Sources/ReadDiceKey",
            swiftSettings: [
                .unsafeFlags(["-O"], .when(configuration: .debug)),
            ]
        ),

        // MARK: Tests
        .testTarget(
            name: "SeededCryptoTests",
            dependencies: ["SeededCrypto"],
            path: "Tests/SeededCryptoTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "ReadDiceKeyTests",
            dependencies: ["ReadDiceKey"],
            path: "Tests/ReadDiceKeyTests",
            resources: [.copy("Fixtures")]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
