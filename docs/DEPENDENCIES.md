# Dependencies, packaging and drift

Everything the app builds from, where it came from, how it is packaged, and what happens
when the original moves. There are no CocoaPods, no git submodules, no SwiftPM package
dependencies and no third-party binaries; `Package.swift` declares zero external packages.

Two ways of carrying upstream code are used, chosen by whether we intend to change it:

- **git subtree** (seeded-crypto): the upstream repo is merged into a directory of this one.
  We can edit it, and `git subtree pull` later merges upstream changes three-way into our
  edits. Use this for anything we may modernize in place.
- **copy + re-vendor script** (libsodium): a plain copy with the upstream commit recorded and
  a script that replaces it wholesale. Use this for things we will never edit.

| Component | Origin | How it is packaged here | Local changes | Drift risk | To update |
|---|---|---|---|---|---|
| libsodium 1.0.22 | jedisct1/libsodium (ISC) | `Packages/DiceKeysCore/Sources/CSodium`: `src/libsodium` copied, compiled from source as a SwiftPM C target. `version.h` generated once by libsodium's configure; x86 `.S` files dropped; an explicit module map. The `HAVE_*` defines configure would set on Apple platforms live in `Package.swift`; `HAVE_PTHREAD` is the one that matters for correctness (without it `sodium_init()` has no lock and concurrent first use aborts in `sodium_free`). | none to the sources | **Real but low.** Security fixes do not arrive automatically (Dependabot cannot see a vendored copy). Nothing else can drift: the algorithms the app relies on (Argon2id, BLAKE2b, XSalsa20-Poly1305, Ed25519, X25519) are frozen by the golden vectors. | `scripts/vendor-libsodium.sh [url] [tag]`, then `scripts/generate-golden-vectors.sh` must produce no diff. Watch libsodium's releases page. |
| seeded-crypto (lib-seeded) | dicekeys/seeded-crypto `primary` @ `c9c7740` (MIT); tracked via the fork **cafedomingo/seeded-crypto** | **git subtree** at `Packages/DiceKeysCore/Vendor/seeded-crypto` (squashed; the whole upstream repo, of which `lib-seeded/` is a SwiftPM C++ target). Our C ABI (`Sources/SeededCryptoNative`) sits on top. | **none to the sources.** Outside `lib-seeded/`: the submodule gitlinks and `.gitmodules` are removed, and `extern/libsodium/` holds only the private argon2 header `recipe.cpp` includes by relative path (force-added past upstream's `extern/**` ignore rule). | **Tracked, mergeable.** `scripts/update-seeded-crypto.sh` runs `git subtree pull`, which three-way merges upstream (or a fork) into whatever we have changed locally. That is what makes modernizing the internals here safe: our edits and upstream's later fixes merge instead of overwriting. `GoldenVectorTests` catches any change to derivation. | `./scripts/update-seeded-crypto.sh [url] [ref]`, then `scripts/generate-golden-vectors.sh` must produce no diff. `git log -- Packages/DiceKeysCore/Vendor/seeded-crypto` shows every upstream commit merged. |
| read-dicekey (scanner) | dicekeys/read-dicekey `primary` @ `0440036` (unlicensed) | **Not vendored any more.** `Packages/DiceKeysCore/Sources/ReadDiceKey` is a pure-Swift port; upstream's 23 test photos and the C++ scanner's output on them are fixtures. | it is a port, not a copy | **Divergence is by design.** Algorithm changes upstream do not flow here. Upstream's last algorithmic change was 2020 (2025's commit only bumped OpenCV). If they ever improve reading, port the change and re-run the corpus. | Diff upstream's `lib-read-dicekey` against the SCANNER-PORT-NOTES stage table; regenerate `reference-cpp-scanner.json` from commit `183d39d` of this repo if the C++ reference is needed again. |
| OCR glyph tables | read-dicekey's generated `inconsolata-700.cpp` | `scripts/ocr-font-source/inconsolata-700.cpp.gz` (source) → `OcrFontTables.swift` (generated, committed). | none | none | `python3 scripts/generate-ocr-font-tables.py` |
| OpenCV | opencv.org | **Removed.** | | none | |
| Inconsolata | Google Fonts (OFL 1.1) | `DiceKeys/fonts/Inconsolata-Bold.otf`, 60 KB, registered in `Info.plist`. | none | none | The physical dice are printed in this face, so the on-screen replicas match what you compare them against. A system monospaced fallback is already wired in. |
| Icon Composer document | Apple `.icon` schema 1.x | `DiceKeys/Resources/AppIcon.icon`, generated from `scripts/app-icon-source/original-mark-1024.png`. | | Apple may extend the schema; validated against the 1.x/2.0 schema. | `python3 scripts/generate-app-icon.py` |
| XcodeGen | yonaskolb/XcodeGen (brew) | build-time tool only; the `.xcodeproj` is generated, not committed. | | Spec format is stable; CI installs the latest. | |
| GitHub Actions | actions/checkout, upload-artifact | `.github/workflows/build.yml` | | Dependabot bumps them. | |
| dicekeys-app-ios (this app) | dicekeys/dicekeys-app-ios `main` @ `543a1b0` | this repository | complete restructure | **Merging upstream is no longer practical**; upstream has been idle since 2022. Cherry-pick by hand if they ever ship a fix. | |

## What to fork

Forks matter for the things we still *track*, not for things we replaced.

- **`cafedomingo/seeded-crypto`** (exists) is what `scripts/update-seeded-crypto.sh` pulls
  from by default. Modernize Stuart's C++ either in the subtree here (then
  `git subtree push --prefix=Packages/DiceKeysCore/Vendor/seeded-crypto <fork-url> <branch>`
  to export) or in the fork (then run the update script). To take upstream changes, pull
  them into the fork first or pass the upstream URL to the script.
- **`cafedomingo/read-dicekey`** (exists) preserves the photo corpus and the C++ reference
  algorithm. Nothing builds from it.
- **`cafedomingo/dicekeys-app-typescript`** (exists) is the independent browser reader /
  deriver, unrelated to this build.
- **No fork needed:** libsodium (re-vendor from release tags), `seeded-crypto-ios`,
  `read-dicekey-ios`, `opencv-xf` (all three are Objective-C++/binary wrappers this repo no
  longer uses; they can be archived).

## Invariants that catch drift

- `GoldenVectorTests`: every derivation output for a fixed seed and 12 recipes, generated from
  the reference C++. Any libsodium or lib-seeded change that alters a byte fails CI.
- `DiceKeySeedTests`: the app's DiceKey canonicalization against the same fixture.
- `ScannerCorpusTests`: all 23 upstream photos read correctly (with upstream's per-photo
  tolerances).
- `ReferenceScannerComparisonTests`: the Swift scanner's per-face output against the C++
  scanner's, rotation-independently.
