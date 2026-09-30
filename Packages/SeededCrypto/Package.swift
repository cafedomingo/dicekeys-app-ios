// swift-tools-version: 6.2
//
// SeededCrypto: DiceKeys' seeded-crypto and the libsodium it builds on, vendored as sources
// so the app builds with no CocoaPods, no submodules, no Objective-C, no third-party
// binaries and no network access beyond what Xcode itself needs.
//
//   CSodium            libsodium 1.0.22 compiled from source (C)
//   SeededCryptoCXX    DiceKeys lib-seeded (C++), a git subtree under Vendor/
//   SeededCryptoNative our C-ABI shim over it
//   SeededCrypto       Swift API used by the app
//
// Provenance: Sources/CSodium/VENDOR.md for the libsodium copy, and THIRD_PARTY_LICENSES
// for the seeded-crypto commit Vendor/seeded-crypto was taken from.

import PackageDescription

let package = Package(
    name: "SeededCrypto",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "SeededCrypto", targets: ["SeededCrypto"]),
        // libsodium itself, for tests that compare a Swift primitive against it. Goes away
        // with the C++.
        .library(name: "CSodium", targets: ["CSodium"]),
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
                // guarded-memory canary is re-randomized under a live allocation, and the
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

        // MARK: Tests
        .testTarget(
            name: "SeededCryptoTests",
            dependencies: ["SeededCrypto"],
            path: "Tests/SeededCryptoTests"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
