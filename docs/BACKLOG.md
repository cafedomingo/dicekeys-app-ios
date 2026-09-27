# Backlog

Work that was deliberately left out of the initial port, because each item is large enough
to deserve its own change. Roughly in the order it is worth doing; the short items at the
end are the exceptions, too small to stand alone but worth not forgetting.

Everything above the Ideas heading is wanted, whether or not it is scheduled. Everything
below it is a question rather than a plan, kept so the reasoning behind it survives, and it
may well be answered by deciding not to do it.

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

## A better scanner, built on Vision

**Why it exists.** The scanner is a faithful port of upstream's OpenCV pipeline, kept
output-identical to the C++ so the port could be proven correct photo by photo
(`docs/SCANNER-PORT-NOTES.md`). Nobody chose it as the best way to find a DiceKey. It is
brute force: every frame is thresholded at twelve fixed brightness levels plus one Canny
edge image, every border at every level is traced and fitted with a rectangle (about 2,100
per frame), and filtering then keeps the 25 to 50 that are shaped like undoverlines. Nearly
all of the work is spent on things that are not a DiceKey, so an ordinary busy scene is the
worst case, which is how one frame of the world crashed a TestFlight build. PR #9 fixed that
and stopped storing the short borders, bringing a busy 1080-pixel frame down to 60 to 80 MB,
but the design is unchanged. The goal is a dramatically better scanner, and with it deleting
code the system frameworks already provide.

**The direction: Apple's Vision framework.** The port notes rejected Vision because its
results cannot be compared with the C++ reference. That constraint goes away once matching
C++ stops being the goal. Vision is maintained by Apple, is built for camera frames of
arbitrary scenes, and takes the camera's `CVPixelBuffer` directly with an orientation and a
region of interest.

**What Vision would replace**, counted in `Packages/DiceKeysCore/Sources/ReadDiceKey/`:

- **Finding candidates.** `DetectRectanglesRequest` (the Swift Vision API) finds
  quadrilaterals, narrowed by `minimumAspectRatio`, `maximumAspectRatio`, `minimumSize` and
  `maximumObservations`. That replaces the contour tracer (`Contours.swift`, 344 lines), the
  blur, Canny, dilate and threshold filters in `GrayImage.swift` (most of its 445), the
  rectangle fitting in `Geometry.swift`, and the thirteen-level search in
  `FindUndoverlines.swift`.
- **Reading the letter and digit.** `RecognizeTextRequest` could replace the template OCR:
  `OCR.swift` (189 lines), the generated `OcrFontTables.swift` (3,741), and with them
  `scripts/generate-ocr-font-tables.py` and `scripts/ocr-font-source/`. Worth knowing: the
  letter and digit are also encoded in both the underline and the overline, and OCR is the
  third vote that decides which line is wrong when the two disagree (`FaceRead.error()`). So
  the question is whether Vision reads single rotated characters well enough to be that
  vote, or whether the two codes alone are enough.
- **Converting the frame.** Each frame is oriented, cropped to a square, turned into a
  `CGImage`, redrawn into an RGBA buffer and converted to gray (`rgbaCenteredSquare` in the
  app, `GrayImage(rgba:)` in the package). Vision needs none of that. Whatever still samples
  pixels (the undoverline dots) could read the camera's luma plane directly.

**What stays**, because it is the DiceKey rather than image processing: reading the eleven
dots of an undoverline and decoding them (`Undoverline.swift`, `FaceSpecification.swift`),
assembling the 5x5 grid (`AssembleDiceKey.swift`), merging reads across frames and deciding
when to stop (`FaceRead.swift`, `DiceKeyReader.swift`).

**Removable now, whatever is decided.** Two things are left over from the C++ interface
rather than needed by the app:

- **The overlay renderer.** `DiceKeyScanner.renderOverlay` and `augment`, with the drawing
  code behind them in `DiceKeyReader.swift`, are called only by tests. The app draws its own
  overlay in SwiftUI (`FacesReadOverlay`).
- **The JSON round trip.** The scanner encodes its result as a JSON string and the app
  decodes it again with `FaceRead.fromJson`, a boundary that existed because the scanner was
  C++ behind a C ABI. A Swift scanner can hand back typed values.

**Unknowns, to settle with a spike before committing.** Whether `DetectRectanglesRequest`
reliably finds bars as thin as undoverlines (width 0.177 of their length) at the angles and
distances a DiceKey is held; whether text recognition reads isolated single characters in
four rotations; and whether Vision runs on the GPU or Neural Engine here rather than the CPU
cores, which is where a battery and heat win would come from. The spike runs Vision over the
corpus and reports what it finds, before any code is removed.

**Correctness without the reference.** Leaving the C++ comparison behind means correctness
rests on the 23 photos in the corpus test still reading correctly, and on scans of real keys.
Grow the corpus before the switch, especially with hard cases: glare, angle, low light, a
key partly out of frame, and busy backgrounds with no key at all.

**Measure first, on a phone.** The 20 ms per frame and the memory figures are from an M2.
Take per-frame time, peak memory and energy on an iPhone for the current scanner before
changing it, so the Vision version is judged against the same numbers.

**Alternatives, if Vision falls short.** Each keeps more of the current code:

- **Scan a smaller frame.** No capture resolution is set, so the full 1080-pixel square is
  scanned. Undoverlines are large at the distance a DiceKey is held, and cost falls roughly
  with area, at some risk to the OCR.
- **Track the key between frames.** Once the grid is found, search near it and fall back to
  the full frame when it is lost; with nothing found, scan every few frames.
- **One pass across all brightness levels.** The twelve thresholds approximate what MSER
  (maximally stable extremal regions) computes directly, with a component tree in
  near-linear time over one pass. The real algorithmic fix within the current design.
- **`DetectContoursRequest`.** Vision's own contour detection in place of the tracer,
  keeping the rectangle fitting and filtering. A smaller step than rectangles, and a smaller
  deletion.
- **A trained detector.** A Core ML model that finds whole faces, trained with Create ML.
  The most capable and the most work, and it needs labelled photos this project does not
  have yet.

## Simpler recipes

**Why it exists.** A recipe can be built from a web address, a purpose, or raw JSON. The web
address is not used as an address: it is hashed like any other string, so it is a purpose
wearing a costume, and it invites the idea that the app knows something about the site. The
built in list is padded with services nobody here uses.

**What is left.** Drop the web address as a way of building a recipe, leaving purpose and a
sequence number, and trim the built in list to what is actually wanted. Keep raw JSON: it is
the escape hatch for reproducing a secret made somewhere else, which matters because the
recipe is hashed into the secret. A recipe that differs by one character is a different
secret, so anyone already using a secret from a web address recipe must still be able to
reproduce it, and raw JSON is how.

## Dark mode

**Why it exists.** The app follows the system appearance (nothing forces light mode), but
most screens were drawn for a white background: hard-coded white and black fills, the
DiceKey and sticker illustrations, and the navy funnel behind derived values. In dark mode
they range from off-palette to unreadable. The privacy cover is the only screen designed
for both.

**There is no one place colours live, which is the real work.** They are in three:
`Colors.xcassets` holds fourteen named colours and not one of them has a dark appearance
variant; thirty-four literals are written inline across fourteen files; and four brand blues
are private constants inside `PrivacyCoverView`, which is the only component that was drawn
for both appearances.

**Two kinds of colour, which the theme has to tell apart.** Interface colours describe a
role: `formHeadingBackground`, `navigationBarForeground`, text on a surface. They have to
change with the appearance. Depiction colours describe a physical object: the blue of the
case, the white of the dice, the white of the sticker sheets. They are closer to a photograph
than to a surface, and re-tinting them for dark mode would be drawing a DiceKey nobody owns.
For those, naming the hue is naming the role, so `alexandrasBlue` is a correct name rather
than a lazy one.

**The split does not follow the existing names.** `alexandrasBlue` is doing both jobs today.
It is the `diceBoxColor` and `diePenColor` that depict the case and its lid, and it is also
the colour of headings such as "Use a Stickeys Kit" in `ChooseBackupTargetView`. As a
depiction it should hold still in dark mode; as heading text it cannot, because a mid blue on
a dark background is unreadable. So the work is not renaming entries, it is deciding at each
use site which of the two a colour is being asked to be.

**Which means the dark appearance has to be chosen around the fixed colours, not the other
way round.** That is the reverse of how this usually goes, and the numbers already rule out
the obvious answer. The DiceKey is itself a dark navy object: `diceBox` is rgb(10, 12, 112),
`diceBoxDieSlot` rgb(4, 2, 64), `funnelBackground` rgb(5, 3, 55). The dark palette already
sitting in `PrivacyCoverView` is navy rgb(22, 28, 72) and midnight rgb(10, 12, 34). The box
and midnight share their red and green exactly and differ only in blue; the die slots land on
top of navy. A navy dark mode would dissolve the DiceKey into its own background, so the
appearance probably has to be neutral, dark grey rather than dark blue, precisely so that a
navy object still reads as an object.

The other half of the same problem is at the light end. `alexandrasBlue` is rgb(85, 118, 197),
a mid blue, which is why it works as heading text on white. On any dark background it is
heading text that has to be lifted, while the same value used as the case has to stay exactly
where it is.

**What is left.** Build the theme first and let dark mode fall out of it. One place that
holds both kinds, distinguishes them, absorbs the brand blues currently hidden in a view, and
replaces the inline literals. Dark mode then becomes filling in a second column for the
interface half, and a screen that looks wrong later is one wrong entry rather than a hunt
through fourteen files.

Every screen still has to be looked at in both appearances, because a theme makes colours
consistent without making contrast correct, and the depiction colours stay put while
everything behind them moves.

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

## iPad, the Mac, and later the foldable

**Why it exists.** The app is built for iPhone and iPad (`TARGETED_DEVICE_FAMILY` is
`1,2`), but no iPad has ever run it. Several screens were laid out against a phone-shaped
canvas, and the backup and validation illustrations already run off the right edge on a
phone.

**What proper iPad support covers.** Four things, roughly in order:

- **Rotation.** The iPad declares all four interface orientations, so item 1 stops being
  cosmetic here: the camera and the interface have to turn together.
- **Wider layouts.** Screens that stretch a phone column across a tablet, and the
  illustrations that already overflow, need layouts that use the width.
- **Resizable windows.** `Info.plist` does not set `UIRequiresFullScreen`, so the app
  already opts into iPad multitasking and its window can be resized freely. Every screen
  has to survive a live resize, and the scanner is the hard case: the preview and the
  overlay have to stay agreed through a size change.
- **Keyboard and pointer.** Hover states and shortcuts for the common actions. The least
  urgent of the four, and the one to drop first if the rest is enough.

**The Mac is the cheap place to test it.** `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD` is on
(the Xcode default), so an Apple silicon Mac runs the unmodified app with the iPad interface,
in a resizable window, with no extra target; Mac Catalyst stays off because nothing needs
it. It has never been run. Three things make it worth doing:

- It is an iPad-idiom, landscape, resizable window, which is most of the list above.
- It has a real camera. The camera fallback for machines with no back camera and the
  unmirrored preview are already in place, so a real DiceKey can be scanned with the
  built-in camera or an iPhone as a Continuity Camera, without installing on a phone.
- It may enforce the keychain's access control, which the Simulator ignores. Unverified.

It is not a replacement for the Simulator, which remains the closer match for an iPhone.

The first run needs the Mac registered as a development device, once. Unlike the Simulator,
real hardware runs only builds whose development profile lists that machine, and this Mac is
not on the team's list yet. TestFlight never needed this because distribution profiles do not
list devices. Either sign into Xcode's Accounts and run the app on My Mac (Designed for iPad),
which registers it automatically, or add the Mac's provisioning UDID by hand in the developer
account. After that the destination is `platform=macOS,variant=Designed for iPad`.

**The iPhone Duo**, Apple's foldable, ships 23 October 2026 with a 5.4-inch outer and a
7.6-inch inner display, and no simulator for it exists in Xcode 27.0. Nothing to do yet.
When it matters, the portrait lock is the first thing to revisit, and the fold transition
resizes the app live, which is the resizable-window problem above arriving on a phone. Work
done for the iPad carries over.

## Smaller items, not worth their own change

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

# Ideas

Not decided, and not commitments. Each records what makes the idea non-obvious, so that
evaluating it later starts from the constraint rather than from scratch.

## Concealing secrets on screen, not just in the snapshot

**Not decided.** Three related ideas, none of them evaluated enough to commit to. They came
out of the privacy cover work and are recorded so the reasoning is not lost.

**Where the cover stops.** The privacy cover follows Apple's QA1838: it appears when the app
backgrounds, because that is when UIKit snapshots the scene for the app switcher. The
snapshot is the only moment the screen becomes something that outlives the user looking at
it, and it is all the cover is for. Everything else the screen shows while the user is
present is untouched. That is deliberate, and it is what Wallet does, but Wallet's card
details are not credentials, so the precedent is weaker here than it looks. Apple has no API
for this in an app: `privacySensitive()` and `RedactionReasons.privacy` are applied by the
system only for widgets on the Lock Screen and Always On displays.

**Re-conceal revealed dice when the scene deactivates.** A revealed DiceKey currently stays
revealed through a Face ID prompt, a Control Center pull, the notification shade, and a
screenshot the user takes. Re-concealing costs nothing in responsiveness, because unlike the
cover there is no automatic reverse to wait on: the user taps to reveal again. The state is
already in one place, `hideDiceExceptCenterDie`, so one write would obscure every DiceKey
view. The wrinkle is that it is an `@AppStorage` preference rather than session state, so
forcing it would overwrite the user's own choice every time a notification arrives. Session
scoped concealment layered over the stored preference avoids that.

**A locked state instead of popping to the home screen.** Keys expire 59 seconds after the
app backgrounds, and `RootView` pops to the root when the foreground key goes, so returning
after a minute lands on the home screen having lost your place. Keeping the route and
rendering a locked DiceKey screen with an unlock action would preserve it, at the cost of one
new piece of state, since `foregroundDiceKeyId` is cleared on expiry and something has to
remember which key to offer. Prompting Face ID automatically on return is the tempting
version and the wrong one: an unrequested biometric prompt every time the user has been away
a minute teaches people to approve prompts without reading them.

**Concealment for derived values.** The largest of the three and the one with no foundation
yet. `DerivedValueScreen` holds its derived value in plain `@State` with no notion of hidden
or shown, so a generated password on screen is always visible and there is nothing to flip.
Giving derived values a hide and reveal is a feature rather than a tweak, and it overlaps the
QR code sheet item, which is about moving those same secrets between devices.

**Worth knowing before committing to any of it.** The switcher can briefly show a stale
snapshot from before the cover was applied, which is visible in other password managers too
and is not something either rule fixes. The only technique that closes it is putting the
content inside a secure text field's layer, which genuinely blocks screenshots, recording and
snapshots, but is undocumented, can break with any iOS release, and would also stop the user
photographing a derived value to move it somewhere.

## A password AutoFill provider

**Not decided.** Today a derived password has to be copied by hand. iOS has a first class
slot for this, `ASCredentialProviderExtension`, which would put DiceKeys in the QuickType bar
above the keyboard when a site asks for a password. It is the feature that would make the app
usable daily rather than deliberately.

**The constraint that shapes everything else.** An AutoFill extension is a separate process
with its own sandbox, so it needs its own route to the DiceKey. That means a shared keychain
access group between app and extension, which widens the set of processes that can ask for
the item. The access control added alongside it makes this less alarming than it sounds: the
keychain demands the user's presence whoever asks, so an extension reading the DiceKey raises
Face ID exactly as the app does. The extension would also have to derive, which means the
crypto has to run there too, and a smaller derivation dependency would help.

**Without a username, what is a credential?** `ASPasswordCredential` takes a user and a
password, and the QuickType suggestions come from identities stored in
`ASCredentialIdentityStore`, keyed on service and user. An empty user is expressible but it
leaves nothing to tell two accounts on one site apart, and with no stored identities there
are no suggestions at all: the user has to open the provider and find the recipe themselves,
which is most of the convenience gone.

**Whether to store usernames.** The app's premise is that nothing is kept and everything is
recomputed. Usernames are not secrets, and recipe names and the list of known DiceKeys are
already stored, so this is a difference of degree. But it is the first stored thing that says
who you are somewhere, rather than what you asked for.

**Whether the username belongs in the salt.** Tempting, and probably wrong. The recipe is
hashed into the secret, so a username in it means a typo produces a different password
silently, and changing your email address later means the password can never be derived
again. The sequence number already exists for wanting more than one secret for one purpose.
Putting the username in the salt duplicates that with a more fragile input.

**Whether the password can fit the site's rules.** Yes, and there is real data for it. Apple
maintains [password-manager-resources](https://github.com/apple/password-manager-resources)
for exactly this audience: `quirks/password-rules.json` maps domains to the rules needed to
generate a password a site will accept, and `quirks/websites-that-append-2fa-to-password.json`
covers sites where a code is appended to the password. It is a data dependency that has to be
vendored or fetched, and it goes stale.

**The trap in applying those rules.** The recipe is the password. Discovering later that a
site caps length at twenty, and shortening the recipe to suit, produces a different password
rather than a shorter one. So rules have to be consulted when a recipe is first created and
recorded in it, not applied afterwards to something already in use.

## Should Argon2id support stay?

**A question, not a plan.** Derivation defaults to BLAKE2b. Argon2id runs only when a recipe
carries `"hashFunction": "Argon2id"`, and nothing in this app's recipe builder can set that
field, so the only route to it is typing raw JSON.

**No published DiceKeys app ever offered it.** Searching the org: the TypeScript app, which
is the flagship, has no reference to Argon2 at all, and neither does the Android app. The
upstream iOS app has exactly one, a `Codable` enum mirroring the JSON format with no control
that sets it. This port dropped even that. So the feature appears to be a library capability
the apps modelled and never surfaced, usable only by someone who read the library's own
documentation.

**What keeping it costs.** It is the sole reason `recipe.cpp` reaches past libsodium's
public API into its bundled Argon2, and the sole reason this port carries a copy of
`argon2.h` alongside the libsodium it compiles. Dropping it would leave derivation needing
exactly one hash function.

**What dropping it costs.** Any recipe anywhere that specifies Argon2id becomes
unreproducible here. That is the same argument that keeps raw JSON in the recipes item: the
escape hatch is only an escape hatch if it can express what other apps could express. Nobody
knows whether such a recipe exists.

## Alternatives for the seeding implementation

**Not decided, but better founded than it started.** The question is whether roughly 2.2 MB
of vendored C source and three hand-written layers are needed to do what this app does.

**What is there now.** `CSodium` compiles libsodium from source; `SeededCryptoCXX` is the
DiceKeys C++ subtree; `SeededCryptoNative` is a C ABI over it; `SeededCrypto` is the Swift
API. libsodium is an independent library, not a DiceKeys one, and seeded-crypto uses it for
nearly everything: BLAKE2b for the HKDF, Argon2id where a recipe asks, X25519 and
XSalsa20-Poly1305 for sealing, Ed25519 for signing.

**What the app actually calls.** It derives key material and formats it: hex, JSON, BIP39,
OpenSSH, OpenPGP. It never seals, unseals, signs or verifies. Grep `DiceKeys/` for `.seal(`,
`.unseal(`, `generateSignature` or `.verify(` and there is nothing; those functions exist in
the Swift package and no screen reaches them. An Unsealing Key recipe produces the key bytes,
not the ability to unseal a message.

**Which is what makes the idea plausible.** The primitives CryptoKit cannot supply,
XSalsa20-Poly1305 and the sealed box construction, are exactly the ones nothing calls.
CryptoKit does have Ed25519 and X25519, which is what the Signing Key and Unsealing Key
recipes need in order to hand over bytes. That leaves BLAKE2b as the only primitive with no
platform equivalent and no way around it, because it is the derivation itself.

**So the shape would be:** one BLAKE2b dependency, CryptoKit for the curves, and the rest
deleted. Four things to establish before believing it:

- `hkdf.cpp` is a custom construction over BLAKE2b, not standard HKDF. It has to be
  reproduced exactly rather than approximated.
- `crypto_box_seed_keypair` is not raw: it takes SHA-512 of the seed and clamps. CryptoKit
  takes the scalar directly, so that step has to be done by hand or the X25519 keys differ.
- The `toJson()` output is seeded-crypto's format, and anything reading it elsewhere expects
  it byte for byte.
- Dropping seal and unseal narrows interoperability with other DiceKeys apps even though
  nothing here uses them. That is a product decision rather than a technical one.

**The golden vectors are the whole proof, and the only one.** Every official implementation
is the same C++ compiled differently: [seeded-crypto-js](https://github.com/dicekeys/seeded-crypto-js)
through Emscripten, [seeded-crypto-ios](https://github.com/dicekeys/seeded-crypto-ios) as a
dormant CocoaPods wrapper, which is what this app moved away from. There is no independent
implementation to check against, so the vectors are not one cross-check among several.

**Related.** Removing Argon2id would leave exactly one hash function to reimplement, and
would retire the internal header include on its own. The two smaller items about Swift and
C++ interop and about modernising the vendored C++ are the incremental version of this.
