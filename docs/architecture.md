# The app, and how to work on it

Companion documents: `derivation.md` (how keys are made), `security.md` (what is stored and
why it is safe), `design.md` (the look), `scanning.md` (how the scanner reads a DiceKey) and
`backlog.md` (what is left).

## The app in one paragraph

DiceKey Vault regenerates a few rarely used keys (SSH, WireGuard, age, passphrases, BIP39
wallet phrases) from a DiceKey, and stores no secret. It is one SwiftUI target (iOS 26 and
later, macOS to follow) on Observation, async/await and Swift 6 strict concurrency, with
Liquid Glass chrome, and no external dependencies. A DiceKey is scanned with the camera or
typed by hand. Two local Swift packages supply the rest: `Derivation` (targets `Derivation`,
for recipes and derived values, and `KeyFormats`, for key encodings and BIP39) and
`ReadDiceKey` (the generated face specification and the DiceKey scanner). There is no Objective-C or C++ in the tree.

## Goals, in priority order

1. **Always be able to read a DiceKey and re-derive the same secrets.** The derivation and
   the scanner are Swift, built from sources in this repository. An independent Python
   implementation and RFC 5869's HKDF vectors guard the derivation output; a corpus of
   photos of real keys guards the scanner. Any change that alters
   derived output is a bug.
2. Build with current Xcode against the current SDKs, Swift 6 language mode, strict
   concurrency, no deprecated APIs. GitHub Actions macOS runners are the compiler for this
   branch, so the SDK floor follows what they ship (Xcode 26.6 today).
3. Liquid Glass throughout: system chrome where possible, explicit glass APIs for custom
   controls, nothing fighting the system look.

## Shape of the app

`ContentView` is a two-column `NavigationSplitView` driven by selection. The sidebar
(`DiceKeyList`, home) lists every DiceKey with its keys and picks a DiceKey, a key, New key
or the scanner; the detail column is a `NavigationStack` showing that, with a key or New key
opened from a `DiceKeyScreen` pushed over it. A phone shows the same columns as a stack.

- **`UnlockedDiceKeys`** (`@Observable`) is the only holder of DiceKeys in memory. The one in
  use, the last opened or unlocked, stays unlocked while the app is open, home included; any
  other locks 59 seconds after it stops being in use, and all lock after the app has been in
  the background that long.
- **The keychain service** (`SavedDiceKeys`) can keep a DiceKey on this device behind user
  presence (Face ID, Touch ID or the passcode). It is never synced or restored elsewhere.
- **The catalog** (SwiftData, `Model/Catalog.swift`: `DiceKeyRecord`, `KeyEntry`) holds only
  non-secret metadata: a DiceKey's one-way id, name and center face, and each key's recipe
  text and public key. The recipe text is the exact bytes the key was derived from, stored
  rather than any Swift type, so the same DiceKey derives the same key from it every time.
- **`Derivation`**: `KeyRecipe` turns a kind and a name into canonical recipe JSON, and
  reads it back only in that form; `DerivedKey` derives and encodes it. `Fixtures/kinds.json` is written by
  `scripts/derive-kinds.py`, an independent implementation.
- **`ReadDiceKey`** is the scanner.

## Directory map

The XcodeGen spec globs all of `DiceKeys/`.

```
DiceKeys/
  App/        DiceKeysApp (entry), ContentView, UnlockedDiceKeys
  Model/      Catalog (SwiftData), DiceKey and its faces
  Services/   things that talk to the OS: Keychain (SavedDiceKeys), Camera, Clipboard
  Features/   one folder per area: DiceKeys (list, screen, grid), Keys (key screens, kinds),
              Load (scanning and manual entry)
  Shared/     PresentableError, the privacy cover
Packages/
  Derivation/ recipes, the engine, key formats; fixtures in Tests/DerivationTests/Fixtures
  ReadDiceKey/ the scanner and its photo corpus
Tests/DiceKeysTests/    Swift Testing
Tests/DiceKeysUITests/  ScreenWalk, run by scripts/screen-walk.sh, not by CI
```

## Compatibility

Everything the app writes outside itself must read the same in every later version, and a
test pins each part. If one fails, the change breaks data already written: fix the change,
never the test. Formats grow only by adding; anything else needs a migration, decided on
purpose.

| What | Pinned by |
|---|---|
| Derived keys, seeds and the DiceKey id (`derivation.md`) | `kinds.json`: `KindVectorTests`, `DiceKeySeedTests` |
| Paper and exported files (`catalog-format.md`) | the v1 fixtures: `CatalogFormatV1Tests` |
| The store, synced to devices on other versions: attributes may be added, never renamed, removed or retyped | `CompatibilityTests` |
| The bundle identifier, store name, sync setting, URL scheme and recovery prefix | `CompatibilityTests` |
| A saved DiceKey: its text, named by its id | `SavedDiceKeysTests` |

## Patterns

- **Errors**: caught into a `PresentableError?` and shown with `.errorAlert(_:)`.
- **Async**: `async/await` and `Task`, and no actors of our own. The only `DispatchQueue`
  is the serial queue AVFoundation requires, where camera frames are scanned.
- **Liquid Glass**: primary controls `.buttonStyle(.glassProminent)`, secondary `.glass`.
  Camera controls sit in one `GlassEffectContainer` (`ScanControls`), falling back to
  `.regularMaterial` under Reduce Transparency. No glass on content.

## Working on it

```
swift run --package-path BuildTools xcodegen generate
open DiceKeys.xcodeproj        # scheme: DiceKeys
```

The Xcode project is generated and git-ignored. **Edit `project.yml`, never the project.**
When Xcode offers to change project settings, cancel: anything it writes is thrown away by
the next `xcodegen generate`, and the prompt comes back. Put the setting in `project.yml`.

Signing needs one per-developer file, `Config/Signing.local.xcconfig`, git-ignored:

```
DEVELOPMENT_TEAM = ABCDE12345
```

Everything else, the bundle identifier included, is a committed default in
`Config/Signing.xcconfig`. The identifier is `com.cafedomingo.dicekeys`, because
`com.dicekeys` belongs to DiceKeys, LLC and identifiers are globally unique.

## Getting a build onto a phone

`scripts/testflight.sh` archives and uploads. Versions are computed at upload time, so
nothing in the repository needs bumping: the marketing version is the build date
(`2026.9.23`) and the build number a minute-resolution timestamp.

This needs a **paid** Apple Developer Program membership. A free Personal Team cannot upload
to App Store Connect at all, and can only install over a cable, or over Wi-Fi after pairing
the phone once in Xcode, with builds expiring after seven days. TestFlight builds expire
after ninety days, which no setting changes; re-running the script is the answer.

Two things trip up a first upload. App Store Connect needs an app record for the bundle
identifier, created by hand under My Apps, and a freshly upgraded membership usually has an
unsigned Program License Agreement, which blocks distribution profiles behind a confusing
permissions error until it is accepted.

## What CI covers

GitHub-hosted macOS runners, currently Xcode 26.6:

- `swift test -c release` for each package: in `Packages/Derivation` the kinds fixture,
  recipe validation, the key formats and RFC 5869's HKDF vectors, and in
  `Packages/ReadDiceKey` the scanner over upstream's photos, the owner's photos and video,
  and drawn keys.
- XcodeGen, then the iOS app built for the simulator and its Swift Testing suite run there.
- On Ubuntu: `swift format lint --strict` (layout is the toolchain formatter's, configured in
  `.swift-format`), SwiftLint, ruff, shellcheck and actionlint, and `derive-kinds.py --tools`,
  which checks the public keys against `ssh-keygen`, `wg` and `age-keygen`.

The runners have no iOS 27 SDK, which is why the deployment target is 26 and the one
27-only API in use sits behind a compile-time SDK gate rather than a runtime `#available`.

## Verified on hardware

Installed from TestFlight on an iPhone: the app runs, the camera previews, and the scanner
reads a real DiceKey at a speed the owner called fine. Rotation was wrong on the device and
has been through two fixes; `backlog.md` records what still needs confirming. The scanner has
since been rewritten (`scanning.md`), and the rewrite has not been on a device yet.

Never run on hardware: this Mac as Designed for iPad, and any iPad at all.

## How the safety nets work

- `Packages/Derivation/Tests/DerivationTests/Fixtures/kinds.json` comes from the independent
  `scripts/derive-kinds.py`. If `KindVectorTests` fails, derived secrets have changed; fix
  the code, not the fixture.
- `Tests/DiceKeysTests/DiceKeySeedTests.swift` ties the app's DiceKey canonicalization to
  seeds recorded from the reference C++, and proves every rotation of a key derives the same
  seed. That last test is
  why the rotation bugs were display problems rather than security ones.
- `Packages/ReadDiceKey/Tests/ReadDiceKeyTests/` runs the scanner over upstream's photos and
  the owner's photos and video (the file names are the expected reads): it must never read a
  face wrong, must read well-framed keys, and must read nothing where there is no key. Keys
  drawn from the face codes cover reading across frames: a quarter turn between frames, a
  second key, a frame that reads nothing.

## Licensing, before this goes anywhere public

seeded-crypto (whose design the derivation follows) and the BIP-39 word list are MIT,
Inconsolata is OFL, the EFF word list is CC BY 4.0, and `THIRD_PARTY_LICENSES` records
each one with its origin and commit. The DiceKeys-derived parts, meaning the scanner and
the photo corpus, still carry only upstream's "all rights reserved while we choose a
license" placeholder. That is why the README says personal use and TestFlight only, and why
publishing needs DiceKeys, LLC to choose a license (license@dicekeys.com).
