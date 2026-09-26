# The app, and how to work on it

Companion documents:
- `BACKLOG.md`: everything deliberately left undone, sized and explained.
- `DEPENDENCIES.md`: every component, how it is packaged, drift risk, how to update.
- `SCANNER-PORT-NOTES.md`: the Swift scanner, stage by stage, and its deliberate differences.

## The app in one paragraph

A single iOS app target: SwiftUI on Observation, `NavigationStack`, async/await and Swift 6
strict concurrency, with Liquid Glass chrome. It scans a physical DiceKey with the camera or
takes one typed by hand, holds it in memory behind Face ID, and derives passwords, keys and
seeds from it. One local Swift package supplies everything native, with no external package
dependencies: libsodium as a source copy, DiceKeys' seeded-crypto as an unmodified git
subtree behind a small C ABI, and a pure-Swift port of the DiceKey scanner. No CocoaPods,
submodules, Objective-C, C++ wrappers or OpenCV remain, and there is not one `#if os(...)`
left in the app.

## Goals, in priority order

1. **Always be able to read a DiceKey and re-derive the same secrets.** The seed derivation
   (seeded-crypto + libsodium) builds from sources in this repository and the scanner is
   pure Swift. Golden vectors generated from the reference implementation guard the
   derivation output; upstream's photo corpus guards the scanner.
2. Build with current Xcode against the current SDKs, Swift 6 language mode, strict
   concurrency, no deprecated APIs. GitHub Actions macOS runners are the compiler for this
   branch, so the SDK floor follows what they ship (Xcode 26.6 today).
3. No Objective-C or Objective-C++ anywhere in the tree.
4. Liquid Glass throughout: system chrome where possible, explicit glass APIs for custom
   controls, nothing fighting the system look.

Nothing here changes what the app derives. Any change that alters derived output is a bug,
and `Packages/DiceKeysCore/Tests/SeededCryptoTests` exists to catch it.

---

## Directory map

The XcodeGen spec globs all of `DiceKeys/`; there are no platform conditionals left (the
macOS target was removed).

```
DiceKeys/
  App/            DiceKeysApp (entry), AppModel (composition root), AppRouter (Route + path),
                  RootView (NavigationStack + destinations + API sheet), HomeView
  Model/          value types and domain logic; nothing here knows about SwiftUI state
    DiceKey/      DiceKey, Face, FaceRead, FaceSpecification, PartialFace,
                  FaceOrientationLetterTrbl+Rotation
    Recipes/      DerivationRecipe (was Derivables), CanonicalizeJsonRecipe,
                  DerivationRecipeTemplates, DerivedValue (was DerivedValueView)
    BIP39/        Mnemonic, Wordlist
    Settings.swift
  Services/       things that talk to the OS
    Keychain/     DiceKeyKeychain (was EncryptedDiceKeyStore)
    Camera/       CameraSession, CameraSampleBufferDelegate, DiceKeyFrameProcessor (actor),
                  ActiveCameras
  Features/       one folder per user-facing feature; views are thin over stores/models
    DiceKey/      DiceKeyMemoryStore, KnownDiceKeysStore, UnlockedDiceKeyState,
                  DiceKeyScreen, SaveDiceKeySheet, SavedDiceKeysView
    Scanning/     ScanDiceKeyView, ScanControls, CameraPreviewView, FacesReadOverlay,
                  DiceKeyScanModel
    ManualEntry/  LoadDiceKeyScreen, TypeYourDiceKeyView, DiceKeyboardView,
                  EditableDiceKeyState
    Recipes/      DerivationRecipeStore, RecipeListView, RecipeSource, RecipeBuilderState,
                  TemplateRecipeBuilder, CustomRecipeModel, CustomRecipeForm, RecipeJsonView,
                  SequenceNumberField, DerivedValueScreen, RecipeCardView,
                  DerivedValueOutputView, DerivedValueQrCodeSheet
    Backup/       BackupDiceKeyView, BackupProgress, ChooseBackupTargetView,
                  ValidateBackupView, DiceKeyKit/*, Stickeys/*
    Assembly/     AssemblyInstructionsScreen
  Shared/
    Components/   Instruction, ActionButtons (PrimaryButton/SecondaryButton), StepFooter,
                  ChildSizeReader, PresentableError (+ .errorAlert)
    DiceKeyRendering/  DiceKeyView, DieView, DiceKeyCenterFaceOnlyView, DerivedFromDiceKey, Funnel
    Extensions/   Color, Data, String, View
    PlatformTypes.swift  (UIFont.inconsolataBold)
  Resources/, fonts/    unchanged
Tests/DiceKeysTests/    Swift Testing: CanonicalizeRecipeJsonTests, MnemonicsTests, DiceKeySeedTests
```

## Patterns (one of each)

- **Stores**: `@MainActor @Observable final class`, persisted with `UserDefaults` behind
  `didSet`. Created once by `AppModel` and injected with `.appEnvironment(model)`; views read
  them with `@Environment(SomeStore.self)`. No `.singleton`/`.shared` anywhere.
- **Navigation**: `AppRouter.path: [Route]` bound to the one `NavigationStack` in `RootView`.
  `Route` is `.loadDiceKey`, `.assemblyInstructions`, `.diceKey`, `.derive(RecipeSource)`.
  Leaving `.diceKey` (any way) starts the memory-store expiration countdown; the key expiring
  pops to root. Sheets: save-to-keychain, custom recipe and QR code, all with
  `.presentationDetents([.medium, .large])`.
- **Errors**: caught into a `PresentableError?` and shown with `.errorAlert(_:)`.
  `UnlockedDiceKeyState.lastError` is the store-side example.
- **Async**: `async/await`, `Task`, one actor (`DiceKeyFrameProcessor`), `Mutex` for the
  frame-drop flag. The only `DispatchQueue` is the serial queue AVFoundation requires.
- **Liquid Glass**: primary CTAs `.buttonStyle(.glassProminent)`, secondary `.glass`
  (`PrimaryButton`/`SecondaryButton`, `StepFooterView`). Camera controls in one
  `GlassEffectContainer` with `.glassEffect(.regular.interactive())` + `.glassEffectID`
  (`ScanControls`), falling back to `.regularMaterial` under Reduce Transparency and skipping the
  morph IDs under Reduce Motion. No glass on content (cards use `GroupBox`). Scroll views under
  bars use `.scrollEdgeEffectStyle(.soft, for: .top)`. `DiceKeyScreen` uses a `TabView` with
  `ToolbarSpacer(.fixed)` between toolbar items and `.tabBarMinimizeBehavior(.onScrollDown)` (iOS).
  Forms use `.formStyle(.grouped)` with title-case section headers.

## Working on it

```
brew install xcodegen
xcodegen generate
open DiceKeys.xcodeproj        # schemes: DiceKeys, DiceKeysCore-Package
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
`com.dicekeys` belongs to DiceKeys, LLC and identifiers are globally unique. The
entitlements file is empty for a related reason: upstream claimed `applinks:dicekeys.app`,
but a universal link only reaches an app the domain owner lists in its
apple-app-site-association file, so that route was never open to this fork.

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

- `swift test -c release` for `Packages/DiceKeysCore`: the golden derivation vectors, the
  scanner over upstream's 23 photos, a face-by-face comparison against the C++ scanner's
  recorded output, and concurrent first use of libsodium.
- XcodeGen, then the iOS app built for the simulator and its Swift Testing suite run there.

The runners have no iOS 27 SDK, which is why the deployment target is 26 and the one
27-only API in use sits behind a compile-time SDK gate rather than a runtime `#available`.

## Verified on hardware

Installed from TestFlight on an iPhone: the app runs, the camera previews, and the scanner
reads a real DiceKey at a speed the owner called fine. Rotation was wrong on the device and
has been through two fixes; `BACKLOG.md` records what still needs confirming.

Never run on hardware: this Mac as Designed for iPad, and any iPad at all.

## How the safety nets work

- `Packages/DiceKeysCore/Tests/SeededCryptoTests/Fixtures/golden-vectors.json` came from the
  reference C++ (`scripts/generate-golden-vectors.sh`). If `GoldenVectorTests` fails, derived
  secrets have changed; do not update the fixture without understanding why.
- `Tests/DiceKeysTests/DiceKeySeedTests.swift` ties the app's DiceKey canonicalization to the
  same fixture, and proves every rotation of a key derives the same seed. That last test is
  why the rotation bugs were display problems rather than security ones.
- `Packages/DiceKeysCore/Tests/ReadDiceKeyTests/` runs the scanner over upstream's photos
  (the file names are the expected reads) and compares it face by face with the C++ scanner's
  recorded output (`reference-cpp-scanner.json`, regenerable from this repo's commit
  `183d39d`).
- Re-vendoring: `scripts/vendor-libsodium.sh [url] [tag]` and
  `scripts/update-seeded-crypto.sh [url] [ref]`; run the golden-vector script after either
  and expect no diff.

## C++ in Swift or Rust: the decision

Keep the C++. `lib-seeded` is about 5k real lines over libsodium and is the reference
implementation shared with the web app; any byte-level divergence in a rewrite silently
changes every derived secret, and the golden vectors can only cover cases someone wrote
down. `lib-read-dicekey` was the exception, because it needed OpenCV: it was ported to Swift
stage by stage and checked face by face against the C++ output (`docs/SCANNER-PORT-NOTES.md`).
The port follows the same algorithm, so it is still covered by the licensing question below.
Rust would add a second toolchain and an FFI layer for no gain on a
single-platform personal app. What *was* removed is every line of Objective-C: the shims are
C++ behind a C header, which Swift imports natively.

## Licensing, before this goes anywhere public

seeded-crypto and the BIP-39 word list are MIT, libsodium is ISC, Inconsolata is OFL, and
`THIRD_PARTY_LICENSES` records each one with its origin and commit. The DiceKeys-derived
parts, meaning the app itself, the scanner port, the photo corpus and the icon mark, still
carry only upstream's "all rights reserved while we choose a license" placeholder. That is
why the README says personal use and TestFlight only, and why publishing needs DiceKeys, LLC
to choose a license (license@dicekeys.com).
