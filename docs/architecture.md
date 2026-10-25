# The app, and how to work on it

Companion documents: `derivation.md` (how keys are made), `security.md` (what is stored and
why it is safe), `catalog-format.md` (the catalog's file, link and code formats), `design.md`
(the look), `scanning.md` (how the scanner reads a DiceKey) and `backlog.md` (what is left).

## The app in one paragraph

DiceKey Vault regenerates a few rarely used keys (SSH, WireGuard, age, passphrases, BIP39
wallet phrases) from a DiceKey, and stores no secret. It is one SwiftUI target (iOS 26 and
later, and Mac Catalyst on the Mac) on Observation, async/await and Swift 6 strict
concurrency, with no external dependencies. A DiceKey is scanned with the camera or typed by
hand. Two local Swift packages supply the rest: `Derivation` (targets `Derivation`, for
recipes and derived values, and `KeyFormats`, for key encodings and BIP39) and `ReadDiceKey`
(the generated face specification with the font the dice are printed in, and the DiceKey
scanner). There is no Objective-C or C++ in the tree.

## Goals, in priority order

1. **Always be able to read a DiceKey and re-derive the same secrets.** The derivation and
   the scanner are Swift, built from sources in this repository, and each is checked against
   something independent of it (`derivation.md`, `scanning.md`). Any change that alters
   derived output is a bug.
2. Build with current Xcode against the current SDKs, Swift 6 language mode, strict
   concurrency, no deprecated APIs. GitHub Actions macOS runners are the compiler, so the SDK
   floor follows what they ship. The runners have no iOS 27 SDK, so the deployment target is
   26.
3. Liquid Glass throughout (`design.md`): system chrome where possible, nothing fighting the
   system look.

## Shape of the app

`ContentView` is a two-column `NavigationSplitView` driven by selection. The sidebar
(`DiceKeyList`, home) lists every DiceKey with its keys and picks a DiceKey, a key, New key
or the scanner; the detail column is a `NavigationStack` showing that, with a key or New key
opened from a `DiceKeyScreen` pushed over it. A phone shows the same columns as a stack.

- **`UnlockedDiceKeys`** (`@Observable`) is the only holder of DiceKeys in memory. The one in
  use, the last opened or unlocked, stays unlocked while the app is open, home included; any
  other locks after the lock delay (`security.md`) once it stops being in use, and all lock
  after the app has been in the background that long.
- **The keychain service** (`SavedDiceKeys`) can keep a DiceKey on this device behind user
  presence (Face ID, Touch ID or the passcode). It is never synced or restored elsewhere.
- **The catalog** (SwiftData, `Model/Catalog.swift`: `DiceKeyRecord`, `KeyEntry`) holds only
  non-secret metadata, enough to derive each key again. `security.md` says what it holds;
  `catalog-format.md` defines its fields and how it travels as a file, a link and a code.
- **`Derivation`**: `KeyRecipe` turns a kind and a name into canonical recipe JSON, and
  reads it back only in that form; `DerivedKey` derives and encodes it. `Fixtures/kinds.json`
  is written by `scripts/derive-kinds.py`, an independent implementation.
- **`ReadDiceKey`** is the scanner.

## Where things live

```
DiceKeyVault/
  App/        entry point, ContentView, UnlockedDiceKeys
  Model/      DiceKey and its faces, the SwiftData catalog, CatalogFile, RecoveryCode, ScannedCode
  Services/   what talks to the OS: Camera, Keychain, Clipboard, DeviceOwner
  Features/   one folder per area: DiceKeys, Keys, Load (scanning and typing), Catalog
              (import, export, restore), Paper, Settings
  Shared/     components used across features, and the layout tokens
Packages/     Derivation, ReadDiceKey
Tests/        DiceKeyVaultTests (Swift Testing), DiceKeyVaultUITests (ScreenWalk, run by
              scripts/screen-walk.sh, not by CI)
```

The XcodeGen spec globs all of `DiceKeyVault/`.

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
- **Async**: `async/await` and `Task`, and no actors of our own. The only `DispatchQueue` in
  the app is the serial queue AVFoundation requires, where camera frames are scanned; the
  scanner itself uses `DispatchQueue.concurrentPerform`.
- **Look**: `design.md`.

## Working on it

```
swift run --package-path BuildTools xcodegen generate
open DiceKeyVault.xcodeproj    # scheme: DiceKeyVault
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

`.github/workflows/build.yml` sets the Xcode version, on GitHub-hosted macOS runners:

- `swift test -c release` for each package: in `Packages/Derivation` the kinds fixture,
  recipe validation, the key formats and RFC 5869's HKDF vectors, and in
  `Packages/ReadDiceKey` the scanner over its photo corpus and drawn keys.
- XcodeGen, then the iOS app built for the simulator and its Swift Testing suite run there.
- On Ubuntu: `swift format lint --strict` (layout is the toolchain formatter's, configured in
  `.swift-format`), SwiftLint, ruff, shellcheck and actionlint, and `derive-kinds.py --tools`,
  which checks the public keys against `ssh-keygen`, `wg` and `age-keygen`.
