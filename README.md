# dicekeys-app-ios

Fork of [dicekeys/dicekeys-app-ios](https://github.com/dicekeys/dicekeys-app-ios), brought onto current Xcode, iOS 26 and Swift 6, with no CocoaPods and no external packages. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

Requires Xcode 26.6 or later; the deployment target is iOS 26. On an Apple silicon Mac the same app runs as "Designed for iPad".

# How to launch the project

Requirements: Xcode 26.6 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```
brew install xcodegen
xcodegen generate
open DiceKeys.xcodeproj
```

Put your Apple Developer team id in `Config/Signing.xcconfig`, select the `DiceKeys` scheme
and a device, then Product → Run.

There is no CocoaPods, no git submodule, no Objective-C and no third-party binary.
libsodium and the DiceKeys seeded-crypto C++ library are vendored as source in
`Packages/DiceKeysCore`; the DiceKey scanner is pure Swift. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md).

## Testing the app

To test the app, you'll need a DiceKey, which is a box of 25 dice, to scan using the camera.

If you don't have a DiceKey, go to https://dicekeys.app, use the feature to generate a random DiceKey, and then print a picture of arrangement of 25 dice to scan from the app. (Or, you can just scan them from one device's screen to another device's camera.

## Building for production

- Bump version and build number in project
- Product menu, Archive option to build an archive
- Window > organizer to open archives window
- Validate app button (optional)
- Distribute app button

## License

Original work in this fork is MIT-licensed (see [LICENSE](LICENSE), © 2026 Patrick Sunday).
Everything taken from elsewhere keeps its own terms, listed in
[THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES). Two of those components, the DiceKeys app
this fork started from and the read-dicekey scanner the Swift scanner is ported from, have
**no open-source license yet** (DiceKeys, LLC: "all rights reserved while we choose a
license"). That is why this fork is for personal use and TestFlight to the owner's own
devices, not for publication, until DiceKeys picks a license. lib-seeded (MIT), libsodium
(ISC), nlohmann/json (MIT), Inconsolata (OFL 1.1) and the BIP-39 word list (MIT) are fine to
redistribute.
