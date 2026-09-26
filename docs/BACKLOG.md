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

## Confirm the keychain's access control on a device

The saved DiceKey now carries `kSecAttrAccessControl` with `.userPresence`, so the keychain
itself demands Face ID, Touch ID or the passcode before returning it, rather than trusting
every caller to have called `authenticate()` first. What is left is confirming that on
hardware. The Simulator has no Secure Enclave and does not enforce the constraint: a read
with no authenticated context still hands back the key there, which is why the tests cover
the item's attributes and the operations around the read instead of the refusal itself. On
a device, check that unlocking a saved DiceKey prompts exactly once, and that merely asking
whether a DiceKey is saved never prompts at all.

Check one more thing while there. Saving and removing a DiceKey call `SecItemAdd` and
`SecItemDelete` on the main actor, from the toggle in `SaveDiceKeySheet`. Neither should
need to authenticate, and neither prompted on the Simulator, but `SecAccessControl.h` warns
that operations on access-control-protected items "can block the execution because of UI
which can appear", and recommends moving them off the main thread or bounding the UI with
`kSecUseAuthenticationContext`. If the toggle ever stalls on a device, that is why, and the
fix is to make `setStored` async rather than to weaken the access control.

## Simpler recipes

**Why it exists.** Recipes still carry the original app's API shape: site templates are
`allow` lists of hosts (`{"allow":[{"host":"*.1password.com"}]}`), which only mattered when
other apps could request secrets for approved sites. This app has no such API, so a recipe
only needs a `purpose` (an app or service name) and a sequence number for when one purpose
needs several secrets. The recipe screen exposes the internal JSON and the list is padded
with site templates most people will not use.

**What is left.** Rebuild recipe creation around "purpose + sequence number", with raw JSON
at most as an advanced option, and trim the built-in list. The recipe JSON is hashed into
the secret, so a new recipe for the same service produces a *different* secret: anyone
already using a secret from an `allow`-style template must still be able to reproduce it,
either by keeping those templates available as legacy recipes or through the raw JSON
option. Recipes stay compatible with other DiceKeys apps only where the JSON is identical.

## Dark mode

**Why it exists.** The app follows the system appearance (nothing forces light mode), but
most screens were drawn for a white background: hard-coded white and black fills, the
DiceKey and sticker illustrations, and the navy funnel behind derived values. In dark mode
they range from off-palette to unreadable. The privacy cover is the only screen designed
for both.

**What is left.** Audit every hard-coded color for a semantic or asset-catalog equivalent
with a dark variant, decide how the physical-object illustrations (white dice, white
sticker sheets) should look on a dark background, and check each screen in both
appearances.

## The QR code sheet

**Why it exists.** The sheet that shows a derived value as a QR code first asks which
device will scan it, then shows a long paragraph of warning text; it reads as a
questionnaire rather than a way to move a secret to another device. The iOS warning says
that tapping the Camera app's banner for a scanned code starts a web search that sends the
secret to the search engine. Whether current iOS still offers a web search for a
plain-text QR code, and whether it is the default action, has not been checked on a
device; test with a throwaway value before rewriting the warning.

**What is left.** Redesign the sheet around the QR code itself, with any warning short and
specific to what current iOS actually does, and consider whether AirDrop or the share
sheet is a better path for the common case of moving a secret between one's own devices.

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
- **SwiftLint** as a build plugin, so Xcode shows violations while editing; CI already
  runs it.
- **The Python generators in Swift.** `generate-app-icon.py` and
  `generate-ocr-font-tables.py` could be Swift scripts (CoreGraphics in place of Pillow),
  dropping Python and scripts/requirements.txt. Both run rarely and their output is committed.
- Two `VERIFY` comments remain in the scanner (`OCR.swift` on unstable sort ties,
  `DiceKeyReader.swift` on the four-second error-correction budget). Both describe
  faithfully ported upstream behaviour and need a key with a persistent bit error to
  exercise, not a code change.
