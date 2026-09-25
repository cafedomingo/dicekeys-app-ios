# Backlog

Work that was deliberately left out of the initial port, because each item is large enough
to deserve its own change. Roughly in the order it is worth doing; the short items at the
end are the exceptions, too small to stand alone but worth not forgetting.

## Rotate the whole app, or nothing

**Why it exists.** The app is locked to portrait on iPhone while the camera rotates
independently, following gravity through `AVCaptureDevice.RotationCoordinator`. That split
is the root of every rotation bug hit so far: the interface stays still, the picture inside
it turns, and the two disagree about which way is up. Upstream has the same problem, so this
is inherited rather than introduced.

**What was already done.** Two bugs were fixed along the way. A hand-written
angle-to-orientation table, written without hardware, was replaced by letting AVFoundation
rotate the frames. Then the preview and the frames were found to be driven by *different*
horizon-level angles, which Apple's own header warns can disagree "in certain combinations
of device and interface orientations"; both now follow one angle.

**What is left.** Decide the model rather than patch the symptoms. Either support interface
rotation everywhere, so the UI and the camera turn together and the iPad keeps all four
orientations, or lock both to portrait and stop tracking gravity at all. The first is more
work and the better answer for the iPad; the second is a deletion.

**Worth knowing.** Rotation has never affected derived secrets. Seed derivation canonicalises
rotation first, and `DiceKeySeedTests` proves all four rotations of a key produce the same
seed. Every rotation bug here has been about what the screen shows.

**When the target reaches iOS 27**, `videoRotationAngleRelativeToDeviceOrientation(_:)`
returns the angle for a given interface orientation directly, which is the clean foundation
for the first option.

## Confirm rotation on a device

Two attempts to reason about the camera's angle convention without hardware were wrong, so
a device still has to confirm that the key read matches the physical key in portrait and
both landscapes. The on-screen angle readout that was added for this came out in review,
because it shipped to users; the check itself needs only a scan in each orientation.

## Keychain access control

**Why it exists.** Face ID, Touch ID or the passcode guards a saved DiceKey only in app
code: `DiceKeyKeychain.getDiceKey` calls `authenticate()` before reading. The keychain item
itself has no `kSecAttrAccessControl`, so any code path that reads it directly gets the raw
key with no prompt.

**What is left.** Save with `SecAccessControlCreateWithFlags(..., .userPresence, ...)` and
pass the `LAContext` from `authenticate()` as `kSecUseAuthenticationContext` so the user is
not prompted twice. Keys already saved without access control need migrating (read after
authenticating, re-save, delete the old item). It needs a device with Face ID or Touch ID
to test.

## Localization

Every user-facing string is a literal. A String Catalog is the modern form, the project
already sets `LOCALIZATION_PREFERS_STRING_CATALOGS` and `STRING_CATALOG_GENERATE_SYMBOLS`,
and nothing else stands in the way. Sizeable only because there are a lot of strings.

## iOS 27 as the deployment target

Blocked on GitHub's runners, which still carry Xcode 26.6 and no iOS 27 SDK. When they
update: set `deploymentTarget` to 27.0 in `project.yml`, drop the `#else` branch in
`Shared/Components/PresentableError.swift`, and consider the camera API in item 1. Nothing
else in the app wants a 27-only API, and the app already compiles against the 27 SDK
locally while keeping 26 as its minimum, so there is no urgency.

## iPad, and later the foldable

No iPad has ever run this. The iPad declares all four interface orientations, which makes
item 1 more than cosmetic there, and several screens were laid out against a phone-shaped
canvas. The backup and validation illustrations already run off the right edge on a phone.

The iPhone Duo, Apple's foldable, ships 23 October 2026 with a 5.4-inch outer and a 7.6-inch
inner display, and no simulator for it exists in Xcode 27.0. Nothing to do yet. When it
matters, the portrait lock is the first thing to revisit, and the fold transition resizes the
app live, which is the same class of problem as rotation: the preview and the overlay have to
stay agreed through a size change.

## Frame conversion performance

The scanner itself went from 49 ms to 20 ms per 1080-pixel frame on an M2 and the owner
found on-device speed fine, so this is opportunistic. What has never been measured is the
work *before* the scanner: each frame is oriented, turned into a `CGImage`, and redrawn into
a byte buffer, which is two passes over every pixel where `CIContext.render(toBitmap:)`
would do one. There is also no capture resolution set, so the session takes its default and
the full square is scanned; a smaller frame would cut scan cost roughly with area, at some
risk to the OCR. Measure before changing either.

## Smaller items, not worth their own change

- **Mac as Designed for iPad** has never been run, though the camera fallback for machines
  with no back camera and the unmirrored preview are both in place for it.
- **Swift/C++ interop** could replace the hand-written C ABI over seeded-crypto.
- **Modernizing the vendored C++** in the subtree is possible now that it is a git subtree;
  the golden vectors would catch any change to derived output.
- **SwiftLint** as a build plugin.
- Two `VERIFY` comments remain in the scanner (`OCR.swift` on unstable sort ties,
  `DiceKeyReader.swift` on the four-second error-correction budget). Both describe
  faithfully ported upstream behaviour and need a key with a persistent bit error to
  exercise, not a code change.
