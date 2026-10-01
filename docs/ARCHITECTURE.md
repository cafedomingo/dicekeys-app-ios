# The app, and how to work on it

What the code and its config cannot say for themselves: the rules the code follows, and the
reasons behind choices that would otherwise look arbitrary. Companion documents:

- `BACKLOG.md`: wanted work, and ideas still being weighed.
- `derivation.md`: how a seed and a recipe become a password or a key, and the contract that
  keeps every derived byte stable.
- `recipe-format.md`: what a recipe may contain, and `recipe-schema.json`, the same as a
  JSON Schema.
- `SCANNING.md`: how the scanner reads a DiceKey, and why it works that way rather than the
  alternatives measured.

## Goals, in priority order

1. **Always be able to read a DiceKey and re-derive the same secrets.** The derivation and
   the scanner are Swift, built from sources in this repository. Vectors recorded from the
   reference implementation guard the derivation output; a corpus of photos of real keys
   guards the scanner.
2. Build with current Xcode against the current SDKs, Swift 6 language mode, strict
   concurrency, no deprecated APIs. GitHub's macOS runners are the compiler, so the SDK floor
   follows what they ship.
3. No external dependencies, and no Objective-C, Objective-C++ or C++ in the tree.
4. Liquid Glass throughout: system chrome and stock styles where possible, explicit glass
   APIs only for custom controls, and no glass on content.

Any change that alters derived output is a bug.

## Conventions

- **State** lives in `@MainActor @Observable` stores created once by `AppModel` and handed
  down with `.appEnvironment(model)`. Views read them from the environment; there are no
  singletons.
- **Navigation** is one `NavigationStack` in `RootView`, driven by `AppRouter.path`.
- **Errors** are caught into a `PresentableError?` and shown with `.errorAlert(_:)`.
- **Concurrency** is async/await with no actors of our own. The only `DispatchQueue` is the
  serial queue AVFoundation requires for camera frames.

## Colors

Every color lives in `DiceKeys/Resources/Colors.xcassets`, and SwiftLint's `color_literal`
rule rejects color values written in Swift. The catalog has four namespaces, so a call site
says which kind of color it wants (`Color.Depiction.diceBox`):

- **`Depiction`**: the physical kit and anything that must look printed: box, dice, stickers,
  the QR code's white background. One value in both appearances, since re-tinting these for
  dark mode would draw a DiceKey nobody owns.
- **`Camera`**: the viewfinder, always dark like the Camera app.
- **`Interface`**: anything on the system background, with a Dark value or a reference to a
  system color.
- **`Brand`**: the icon's blues and the privacy cover's mesh.

The only real decision is between `Depiction` and `Interface`: if it depicts the kit or
paper, it is a depiction; if it only makes sense against the screen behind it, it is
interface. The DiceKey is navy, which has almost no contrast against a dark background, so in
dark mode it gets a faint edge rather than a new color.

`ColorCatalogTests` enforces the namespaces and `ColorContrastTests` the contrast. The latter
also resolves each system color reference, because `actool` accepts any reference name,
misspelled ones included; a new reference needs a line there too.

## Working on it

```
swift run --package-path BuildTools xcodegen generate
open DiceKeys.xcodeproj
```

The Xcode project is generated and git-ignored. **Edit `project.yml`, never the project.**
When Xcode offers to change project settings, cancel and put the setting in `project.yml`;
anything Xcode writes is thrown away by the next `xcodegen generate`.

Signing needs one git-ignored file, `Config/Signing.local.xcconfig`, holding
`DEVELOPMENT_TEAM = <your team id>`. The bundle identifier is `com.cafedomingo.dicekeys`
because `com.dicekeys` belongs to DiceKeys, LLC. The entitlements are empty because a
universal link to `dicekeys.app` only reaches an app the domain owner lists, so that route was
never open to this fork.

## Getting a build onto a phone

`scripts/testflight.sh` archives and uploads, computing the version at upload time, so
nothing in the repository needs bumping. It needs a **paid** Apple Developer Program
membership: a free Personal Team cannot upload to App Store Connect. TestFlight builds expire
after ninety days; re-running the script is the answer.

Two things trip up a first upload. App Store Connect needs an app record for the bundle
identifier, created by hand under My Apps, and a freshly upgraded membership usually has an
unsigned Program License Agreement, which blocks distribution profiles behind a confusing
permissions error until it is accepted.

## Safety nets

- `Packages/Derivation/Tests/DerivationTests/Fixtures/vectors.json` was recorded from the
  reference C++, which is no longer in the tree, so it cannot be regenerated. If
  `VectorTests` fails, derived secrets have changed: fix the code, not the fixture.
- `DiceKeySeedTests` ties the app's DiceKey canonicalization to the same fixture and proves
  every rotation of a key derives the same seed, which is why rotation bugs are display
  problems rather than security ones.
- The scanner's corpus tests must never read a face wrong and must read nothing where there
  is no key. The photo file names are the expected reads.
