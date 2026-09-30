# The app, and how to work on it

Companion documents:
- `BACKLOG.md`: everything deliberately left undone, sized and explained.
- `derivation.md`: how a seed and a recipe become a password or a key, and the contract that
  keeps every derived byte stable.
- `recipe-format.md`: what a recipe may contain, and `recipe-schema.json`, the same as a
  JSON Schema.
- `SCANNING.md`: how the scanner reads a DiceKey, and why it works that way rather than the
  alternatives measured.

## The app in one paragraph

A single iOS app target: SwiftUI on Observation, `NavigationStack`, async/await and Swift 6
strict concurrency, with Liquid Glass chrome. It scans a physical DiceKey with the camera or
takes one typed by hand, holds it in memory behind Face ID, and derives passwords, keys and
seeds from it. Two local Swift packages supply the rest, with no external dependencies:
`Derivation` (targets `Derivation`, for recipes and derived values, `KeyFormats`, for signing
key exports and BIP39, and `BLAKE2`, the hash the derivation is built on) and `ReadDiceKey`
(the generated face specification and a DiceKey scanner written in Swift).
No CocoaPods, submodules, Objective-C, C++ wrappers or OpenCV remain, and there is not one
`#if os(...)` left in the app.

## Goals, in priority order

1. **Always be able to read a DiceKey and re-derive the same secrets.** The derivation and
   the scanner are Swift, built from sources in this repository. Vectors recorded from the
   reference implementation guard the derivation output; a corpus of photos of real keys
   guards the scanner.
2. Build with current Xcode against the current SDKs, Swift 6 language mode, strict
   concurrency, no deprecated APIs. GitHub Actions macOS runners are the compiler for this
   branch, so the SDK floor follows what they ship (Xcode 26.6 today).
3. No Objective-C or Objective-C++ anywhere in the tree.
4. Liquid Glass throughout: system chrome where possible, explicit glass APIs for custom
   controls, nothing fighting the system look.

Nothing here changes what the app derives. Any change that alters derived output is a bug,
and `Packages/Derivation/Tests/DerivationTests` exists to catch it.

---

## Directory map

The XcodeGen spec globs all of `DiceKeys/`; there are no platform conditionals left (the
macOS target was removed).

```
DiceKeys/
  App/            DiceKeysApp (entry), AppModel (composition root), AppRouter (Route + path),
                  RootView (NavigationStack + destinations + API sheet), HomeView
  Model/          value types and domain logic; nothing here knows about SwiftUI state
    DiceKey/      DiceKey, Face, PartialFace,
                  FaceOrientationLetterTrbl+Rotation
    Recipes/      DerivationRecipe (was Derivables), DerivableType+Descriptions,
                  DerivationRecipeTemplates, DerivedValue (was DerivedValueView)
    Settings.swift
  Services/       things that talk to the OS
    Keychain/     DiceKeyKeychain (was EncryptedDiceKeyStore)
    Camera/       CameraSession, CameraSampleBufferDelegate, ActiveCameras
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
    DiceKeyRendering/  DiceKeyView, DiceKeyOutline, DieView, DiceKeyCenterFaceOnlyView,
                       DerivedFromDiceKey, Funnel
    Extensions/   Data, String, View
    PlatformTypes.swift  (UIFont.inconsolataBold)
  Resources/, fonts/    Colors.xcassets (see Colors), Assets.xcassets, AppIcon.icon
Tests/DiceKeysTests/    Swift Testing
Tests/DiceKeysUITests/  ScreenWalk, run by scripts/screen-walk.sh, not by CI
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
- **Async**: `async/await` and `Task`, and no actors of our own. The only `DispatchQueue`
  is the serial queue AVFoundation requires, where camera frames are scanned.
- **Liquid Glass**: primary CTAs `.buttonStyle(.glassProminent)`, secondary `.glass`
  (`PrimaryButton`/`SecondaryButton`, `StepFooterView`). Camera controls in one
  `GlassEffectContainer` with `.glassEffect(.regular.interactive())` + `.glassEffectID`
  (`ScanControls`), falling back to `.regularMaterial` under Reduce Transparency and skipping the
  morph IDs under Reduce Motion. No glass on content (cards use `GroupBox`). Scroll views under
  bars use `.scrollEdgeEffectStyle(.soft, for: .top)`. `DiceKeyScreen` uses a `TabView` with
  `ToolbarSpacer(.fixed)` between toolbar items and `.tabBarMinimizeBehavior(.onScrollDown)` (iOS).
  Forms use `.formStyle(.grouped)` with title-case section headers.

## Colors

Every color lives in `DiceKeys/Resources/Colors.xcassets`, and SwiftLint's `color_literal`
rule rejects color values written in Swift. The catalog has four namespaces, so a call site
reads `Color.Depiction.diceBox` and says which kind of color it wants:

- **`Depiction`**: the physical kit and anything that must stay printed-looking, such as the
  box, dice, stickers, the funnel out of the box and the QR code's white background. One
  value, in both appearances: re-tinting these for dark mode would draw a DiceKey nobody owns.
- **`Camera`**: the viewfinder, always dark like the Camera app.
- **`Interface`**: anything that sits on the system background, with a Dark value or a
  reference to a system color.
- **`Brand`**: the icon's blues and the privacy cover's mesh. `scripts/generate-app-icon.py`
  reads its box color from here too.

The accent is `AccentColor` at the catalog root: the original's blue, deepened in dark mode
just enough that the stock white label on a filled button stays legible. Choosing between `Depiction` and
`Interface` is the only real decision: if it depicts the kit or paper, it is a depiction; if
it only makes sense against the screen behind it, it is interface.

The DiceKey is a navy object, and navy has almost no contrast against a dark background, so
in dark mode it gets a faint edge (`Interface.objectEdge`, drawn by `DiceKeyOutline`) rather
than a new color. `ColorCatalogTests` enforces the namespaces' rules and
`ColorContrastTests` the contrast the palette promises. The latter also resolves each system
reference against the color it stands for, because `actool` accepts any reference name,
misspelled ones included; a new reference needs a line there too.

Illustrations are SVGs with their vector data kept. Line art gets a Dark variant generated by
`scripts/generate-dark-illustrations.swift`; single-color icons are templates.
`scripts/screen-walk.sh` screenshots every screen in both appearances, for judging a visual
change.

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

- `swift test -c release` for each package: in `Packages/Derivation` the recorded vectors,
  recipe validation, the key formats and the BLAKE2b known answers, and in
  `Packages/ReadDiceKey` the scanner over upstream's photos, the owner's photos and video,
  and drawn keys.
- XcodeGen, then the iOS app built for the simulator and its Swift Testing suite run there.

The runners have no iOS 27 SDK, which is why the deployment target is 26 and the one
27-only API in use sits behind a compile-time SDK gate rather than a runtime `#available`.

## Verified on hardware

Installed from TestFlight on an iPhone: the app runs, the camera previews, and the scanner
reads a real DiceKey at a speed the owner called fine. Rotation was wrong on the device and
has been through two fixes; `BACKLOG.md` records what still needs confirming. The scanner has
since been rewritten (`SCANNING.md`), and the rewrite has not been on a device yet.

Never run on hardware: this Mac as Designed for iPad, and any iPad at all.

## How the safety nets work

- `Packages/Derivation/Tests/DerivationTests/Fixtures/vectors.json` was recorded from the
  reference C++ and cannot be regenerated. If `VectorTests` fails, derived secrets have
  changed; fix the code, not the fixture.
- `Tests/DiceKeysTests/DiceKeySeedTests.swift` ties the app's DiceKey canonicalization to the
  same fixture, and proves every rotation of a key derives the same seed. That last test is
  why the rotation bugs were display problems rather than security ones.
- `Packages/ReadDiceKey/Tests/ReadDiceKeyTests/` runs the scanner over upstream's photos and
  the owner's photos and video (the file names are the expected reads): it must never read a
  face wrong, must read well-framed keys, and must read nothing where there is no key. Keys drawn from the face
  codes cover reading across frames: a quarter turn between frames, a second key, a frame
  that reads nothing.

## C++ in Swift or Rust: the decision

The derivation was C++ (`lib-seeded`, about 5k lines, shared with the web
app). The risk was a byte-level divergence silently changing every derived
secret, so the port was checked three ways: 168 vectors recorded from the C++, the official
BLAKE2b known answers for the one primitive written here, and, while the C++ was still in
the tree, byte-for-byte comparison of the two. `lib-read-dicekey` was ported to Swift stage by
stage and checked face by face against the C++ output, then rewritten around the two bar
codes once the port showed what mattered (`SCANNING.md`); it still follows upstream's approach
to finding and decoding the bars, so it is covered by the licensing question below. Rust would
have added a second toolchain and an FFI layer for no gain on a single-platform personal app.

## Licensing, before this goes anywhere public

seeded-crypto (the origin of the derivation port) and the BIP-39 word list are MIT,
Inconsolata is OFL, the BLAKE2 test vectors are CC0, and `THIRD_PARTY_LICENSES` records
each one with its origin and commit. The DiceKeys-derived
parts, meaning the app itself, the scanner, the photo corpus and the icon mark, still
carry only upstream's "all rights reserved while we choose a license" placeholder. That is
why the README says personal use and TestFlight only, and why publishing needs DiceKeys, LLC
to choose a license (license@dicekeys.com).
