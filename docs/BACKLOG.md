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

**Worth knowing.** Rotation has never affected derived secrets. Seed derivation canonicalizes
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

**Why it exists.** A recipe can be built from a web address, a purpose, or raw JSON. The web
address is not used as an address: it is hashed like any other string, so it is a purpose
wearing a costume, and it invites the idea that the app knows something about the site. The
built in list is padded with services nobody here uses.

**What is left.** Drop the web address as a way of building a recipe, leaving purpose and a
sequence number, and trim the built in list to what is actually wanted. Keep raw JSON: it is
the escape hatch for reproducing a secret made somewhere else, which matters because the
recipe is hashed into the secret. A recipe that differs by one character is a different
secret, so anyone already using a secret from a web address recipe must still be able to
reproduce it, and raw JSON is how. Dropping the web address lands with the Swift derivation
work; trimming the built in list is still open.

## The password screen

**In progress.** Spec on the `password-screen` branch,
`docs/superpowers/specs/2026-10-02-password-screen-design.md`. The custom password sheet
becomes a generator in 1Password's shape: Memorable Password (words), Random Password
(characters) and PIN Code (digits), a length slider, separator and capitalization choices,
a live preview and a strength bar scored on zxcvbn's bands. Three new word lists, EFF's
large list, 1Password's and a curated emoji list, and three new recipe fields, all salt to
other implementations, so a recipe written without them derives and spells as it always
did. Raw JSON moves to its own sheet. Three stacked PRs; this item goes when the last lands.

## A hash function selector

**Decided.** HKDF-SHA-512 through CryptoKit, standard RFC 5869 with no code of our own,
becomes the second `hashFunction` and the default for new recipes; BLAKE2b stays for every
existing one. An unknown name fails, nothing falls back. Slow functions such as Argon2id
buy nothing for a 196-bit seed. Split from the password screen because it is a Derivation
change with its own vectors; the sheet gains the selector once the function exists.

## The derive screen

**Why it exists.** The screen that shows a derived value grew by accretion: recipe card,
format picker, QR button, funnel illustration, copy button. It wants a redesign as a whole
rather than more additions. When that happens, the strength readout the password sheet is
getting belongs here too, and the QR code sheet below is part of the same redo.

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

## Xcode 27, Swift 6.4 and iOS 27, together

Blocked on GitHub's runners: the stable image carries Xcode 26.6 (Swift 6.3.3), and the
`xcode-27` image is still marked preview. CI pins Xcode 26.6 by path so an image update
cannot move the compiler under a green build, and the three packages state
`swift-tools-version: 6.3` as the floor that pin supports. When the Xcode 27 image leaves
preview, move everything in one change: `runs-on` and `DEVELOPER_DIR` in `build.yml`,
`xcodeVersion` and `deploymentTarget` 27.0 in `project.yml`, tools-version 6.4 in
`BuildTools`, `Packages/Derivation` and `Packages/ReadDiceKey`, and the README's Xcode
line. Then drop the `#else` branch in `Shared/Components/PresentableError.swift` and
consider the camera API in item 1. Nothing else wants a 27-only API, and the app already
builds against the 27 SDK locally, so there is no urgency.

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

## Replace upstream's test photos before publishing

**Why it exists.** Most of the scanner's photo corpus comes from read-dicekey, which grants no
license, so those photos cannot be redistributed. The owner's photos can. Nothing needs to
change while the repository stays private.

**What is left.** Photograph test keys to stand in for upstream's photos, then delete them;
`Fixtures/images/README.md` lists which are upstream's. Besides well-framed keys they cover
what the owner's photos do not yet: a key in an open box, a faded print, a key printed on
paper, very low resolution, a photo at an angle, and an image that once crashed the scanner.
The recorded total in `ScannerCorpusTests` then resets to what the new photos read.

## Argon2id, for parity

Wanted only so that a recipe written for the reference C++ library derives here too; no
DiceKeys app ever offered it. RFC 9106 over our BLAKE2b: `H'`, the compression function `G`, memory
filling with Argon2id's switch from data-independent to data-dependent addressing, and
multi-lane support because the RFC vectors use four lanes. About 300 to 400 lines. Verify
against the RFC vectors and against the legacy cases in the fixture, which cover the
arbitrary-length salt (type string plus recipe) and outputs over 64 bytes that the RFC
vectors do not. The default 64 MiB with two passes should take well under a second in Swift.

## A compressed DiceKey format

A binary form of a DiceKey for storage and transfer, not for seeding: the seed stays the
75-character string, or every derived value would change. Naive packing is 10 bits per die
(letter 5, digit 3, orientation 2), 32 bytes. The letters are a permutation, so a mixed-radix
rank of 25! × 6²⁵ × 4²⁵ / 4, about 2¹⁹⁶, fits in 25 bytes, and 19 without orientations.
Decide the consumer first (keychain, QR backup, sharing), since that decides whether the
seven bytes matter.

## Smaller items, not worth their own change

- **SwiftLint** as a build plugin, so Xcode shows violations while editing; CI already
  runs it.
- **The Python generator in Swift.** `generate-app-icon.py` could be a Swift script
  (CoreGraphics in place of Pillow), dropping Pillow and scripts/requirements.txt. It runs
  rarely and its output is committed.
- **Three small interface bugs** found while screenshotting every screen for dark mode:
  the raw JSON recipe warning shows two Cancel buttons; the assembly warning banner is
  clipped at both edges on the backup-choice step; "OpenSSH Private Key" wraps to three lines
  in the output format picker.

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

## Type only the dice the scanner cannot read

**Not decided.** A die whose underline or overline is damaged can never be scanned, because
a face is read only when both lines agree, and today that means typing in the whole key.
Scanning what it can and asking only for the rest would save typing 24 dice to fix one.

**Why it looks cheap.** The scanner knows which slots it has read and never guesses at the
others, and manual entry already holds a key of partially entered faces
(`EditableDiceKeyState`, `PartialFace`). Handing the scanned faces over would leave the user
only the gaps.

**What to settle first.** A typed face has no second line to check it against, so the screen
should make plain which dice were typed. And scanned rotations are relative to the top of the
key as the camera saw it, so the partial key has to be shown that way up for typed rotations
to agree with it.

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
