# Backlog

Work left to do, each item large enough for its own change, roughly in the order it is worth
doing. Ideas, at the end, are questions rather than plans.

## Next

1. **Run on a device.** The scanner, the keychain prompt, Reveal, Copy and Share have only
   run in the Simulator.
2. **Check iCloud sync across two devices.** It is built (Settings, Sync with iCloud) and
   signed for the container, but has only been opened, never synced between devices. Before
   shipping, deploy the CloudKit schema to production in the CloudKit console.
3. **The Mac.** The app runs on Apple silicon Macs as Designed for iPad, with no code of its
   own: put a team id in `Config/Signing.local.xcconfig` and run on My Mac (Designed for
   iPad) once from Xcode, which registers the Mac. Mac Catalyst, for a Mac-style app, can
   follow if the iPad look grates.
4. **The app icon** from `docs/design/` in Icon Composer.
5. **A short written guide** to assembling and backing up a DiceKey, with photographs.

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
rotation everywhere, so the UI and the camera turn together, or lock both to portrait and stop
tracking gravity at all. The first is more work and the better answer on iPad and Mac, where
windows resize; the second is a deletion.

**Worth knowing.** Rotation has never affected derived secrets. Seed derivation canonicalizes
rotation first, and `DiceKeySeedTests` proves all four rotations of a key produce the same
seed. Every rotation bug here has been about what the screen shows.

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

Check one more thing while there. Saving and forgetting a DiceKey call `SecItemAdd` and
`SecItemDelete` on the main actor, from `SavedDiceKeys`. Neither should
need to authenticate, and neither prompted on the Simulator, but `SecAccessControl.h` warns
that operations on access-control-protected items "can block the execution because of UI
which can appear", and recommends moving them off the main thread or bounding the UI with
`kSecUseAuthenticationContext`. If the toggle ever stalls on a device, that is why, and the
fix is to make `save` and `delete` async rather than to weaken the access control.

## A faster scanner

**Why it exists.** The scanner was rewritten around the two bar codes on each face, and
Apple's Vision framework was measured and ruled out along the way; `scanning.md` has both. On
an M2 it scans a frame in 5.4 ms against the original's 21.7, largely by spreading its work
over more cores, and needs about 8 MB more while scanning. It still thresholds the whole frame
twelve times and labels every dark region at each level, and no phone has measured it.

**What is left, in order.**

- **A phone baseline.** Time, peak memory and energy per frame on an iPhone.
- **A cheaper step 2.** Adaptive thresholding (each pixel against the mean of its neighborhood,
  a box blur vImage provides) could replace the twelve thresholds with one, labeling the
  regions once rather than twelve times, the standard design for fiducial markers such as QR
  codes and AprilTags. Spike it against the corpus, and keep it only if it reads at least as
  many faces with none wrong.
- **Then, only if the phone needs it,** a smaller frame (on the corpus cropped to the app's
  square, the port read 412 faces at 540 pixels against 417 at 1080, for about a third of the
  work) or following the key between frames and searching
  only near where it was.

## Localization

Every user-facing string is a literal. A String Catalog is the modern form, the project
already sets `LOCALIZATION_PREFERS_STRING_CATALOGS` and `STRING_CATALOG_GENERATE_SYMBOLS`,
and nothing else stands in the way. Sizeable only because there are a lot of strings.

## Names typed with smart punctuation

A key's name is part of its recipe, and iOS keyboards may turn `'` into `’` and `--` into `—`
even with autocorrection off. A name typed that way on a phone can't be typed again on a
keyboard that doesn't, so the key would be lost to anyone retyping it from memory. Check on a
device; if it happens, turn smart punctuation off for the name field (UIKit's
`smartQuotesType`) or refuse those characters when a name is made.

## Locking with several windows

`UnlockedDiceKeys` is shared by every scene, so on an iPad or Mac with two windows, the
selection in one decides whether the other counts down, and one window going to the
background starts the countdown for both. Fine with one window; worth a per-scene selection
once the Mac target lands.

## Replace upstream's test photos

**Why it exists.** Most of the scanner's photo corpus comes from read-dicekey. The scanner
should be proved by the owner's own photographs of the owner's own keys, wanted whether or
not the repository is ever published; that those photos can also be redistributed, and
upstream's cannot, is a bonus rather than the reason.

**What is left.** Delete upstream's 23 photos; `Fixtures/images/README.md` lists which they
are. Most need no replacement: the owner's photos already cover glare, angle, dim light and
fingers; very low resolution is a downscaled copy of one of the owner's; and the white-box
and printed-paper photos show pre-production keys no one owns. Photograph throwaway test keys
for the rest, each well-framed photo reading at least 20 faces and none misreading:

- A strong shadow across half the key.
- The box turned 180°, as a phone held upside down sees it.
- For `other/`, the lid half closed over the top rows, which must never misread.
- A box mixing dice from two kits, so a letter repeats: every face must read correctly and
  the scan must never finish.
- A finished Stickeys backup, every sticker placed, since restoring from one is scanning it.
- The box held up to a Mac's built-in camera, the one the app uses on a Mac, standing in for
  upstream's crash input.

The corpus totals in `ScannerCorpusTests` then reset to what remains.

## Smaller items, not worth their own change

- **SwiftLint** as a build plugin, so Xcode shows violations while editing; CI already
  runs it.

# Ideas

Not decided, and not commitments. Each records what makes the idea non-obvious, so that
evaluating it later starts from the constraint rather than from scratch.

## Concealing secrets on screen, not just in the snapshot

**Not decided.** The privacy cover follows Apple's QA1838: it appears when the app
backgrounds, because that is when UIKit snapshots the scene for the app switcher. A revealed
secret and the DiceKey's grid also hide when the screen is recorded or a screenshot is taken,
but the screenshot itself can't be stopped, and Apple has no app API for more:
`privacySensitive()` is applied by the system only for widgets on the Lock Screen and Always
On displays.

The switcher can briefly show a stale snapshot from before the cover was applied, as in other
password managers. The only technique that closes it is putting the content inside a secure
text field's layer, which blocks screenshots, recording and snapshots, but is undocumented
and can break with any iOS release.

## Type only the dice the scanner cannot read

**Not decided.** A die whose underline or overline is damaged can never be scanned, because
a face is read only when both lines agree, and today that means typing in the whole key.
Scanning what it can and asking only for the rest would save typing 24 dice to fix one.

**Why it looks cheap.** The scanner knows which slots it has read and never guesses at the
others, and manual entry already holds a key of partially entered faces
(`TypedDiceKey`, `PartialFace`). Handing the scanned faces over would leave the user only the
gaps.

**What to settle first.** A typed face has no second line to check it against, so the screen
should make plain which dice were typed. And scanned rotations are relative to the top of the
key as the camera saw it, so the partial key has to be shown that way up for typed rotations
to agree with it.
