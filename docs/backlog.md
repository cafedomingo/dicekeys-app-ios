# Backlog

Work left to do, roughly in the order it is worth doing, each item large enough for its own
change. The Ideas at the end are questions rather than plans.

## Run on a device

The rewritten scanner (`scanning.md`), the keychain prompt, Reveal, Copy and Share have not
been tried on a device. Check:

- The scanner on an iPhone: a well-framed key reads in a few frames, and the phone stays cool.
  Record time, peak memory and energy per frame, the baseline "A faster scanner" needs.
- The key read matches the physical key in portrait and in both landscapes (see "Rotate the
  whole app, or nothing").
- Unlocking a saved DiceKey prompts exactly once, and asking whether a DiceKey is saved never
  prompts. The Simulator has no Secure Enclave and doesn't enforce `.userPresence`: a read
  with no authenticated context still returns the key there, so the tests cover the item's
  attributes and the operations around the read, not the refusal.
- Saving and forgetting a DiceKey don't stall the toggle. `SavedDiceKeys` calls `SecItemAdd`
  and `SecItemDelete` on the main actor, and `SecAccessControl.h` warns that operations on
  protected items "can block the execution because of UI which can appear". If they stall,
  make `save` and `delete` async rather than weaken the access control.

## Check iCloud sync across two devices

It is built (Settings, Sync with iCloud) and signed for the container, but has only been
opened, never synced between devices. Before shipping, deploy the CloudKit schema to
production in the CloudKit console.

## The Mac

The app runs on Apple silicon Macs as Designed for iPad, with no code of its own: put a team
id in `Config/Signing.local.xcconfig` and run on My Mac (Designed for iPad) once from Xcode,
which registers the Mac. `project.yml` sets `SUPPORTS_MACCATALYST: NO`. Mac Catalyst, for a
Mac-style app, can follow if the iPad look grates. What it would add, from `design.md`:

- A floating glass sidebar listing DiceKeys with their keys nested beneath, and toolbar
  actions in glass capsules at the top right.
- Scanning with the Mac's camera or Continuity Camera, filling the detail pane.
- Reading a DiceKey on the phone and deriving on the Mac, though a Mac's webcam is a fine
  place to scan too.

## A short written guide

Assembling and backing up a DiceKey, with photographs.

## Rotate the whole app, or nothing

The app is locked to portrait on iPhone while the camera rotates independently, following
gravity through `AVCaptureDevice.RotationCoordinator`. The interface stays still, the picture
inside it turns, and the two disagree about which way is up. Upstream has the same problem.

Decide the model rather than patch the symptoms. Either support interface rotation
everywhere, so the UI and the camera turn together, or lock both to portrait and stop
tracking gravity. The first is more work and the better answer on iPad and Mac, where windows
resize; the second is a deletion. Either way, a device has to confirm that the key read
matches the physical key in portrait and both landscapes: reasoning about the camera's angle
convention without hardware was wrong twice.

Rotation never affects derived secrets: `DiceKeySeedTests` proves all four rotations of a key
produce the same seed. Every rotation bug here has been about what the screen shows.

## A faster scanner

The scanner thresholds the whole frame twelve times and labels every dark region at each
level (`scanning.md`). In order:

- **A phone baseline.** See "Run on a device".
- **A cheaper step 2.** Adaptive thresholding (each pixel against the mean of its
  neighborhood, a box blur vImage provides) could replace the twelve thresholds with one,
  labeling the regions once, the standard design for fiducial markers such as QR codes and
  AprilTags. Spike it against the corpus, and keep it only if it reads at least as many faces
  with none wrong.
- **Then, only if the phone needs it,** a smaller frame (on the 23-photo corpus, before step 5
  and cropped to the app's square, 540 pixels read 412 faces against 417 at 1080, for about a
  third of the work; measure again), or
  following the key between frames and searching only near where it was.

## Passphrase lists as JSON

Move the EFF large wordlist and the two character sets into JSON files the Derivation package
loads as resources, which `scripts/derive-kinds.py` reads too instead of scraping Swift
source. The lists become part of the spec next to `kinds.json`. Changing where they live
changes no key.

## Localization

Every user-facing string is a literal. A String Catalog is the modern form, the project
already sets `LOCALIZATION_PREFERS_STRING_CATALOGS` and `STRING_CATALOG_GENERATE_SYMBOLS`,
and nothing else stands in the way. Sizeable only because there are a lot of strings.

## Names typed with smart punctuation

iOS keyboards may turn `'` into `’` and `--` into `—` even with autocorrection off, and a
key's name is part of its recipe, where `'` is not `’` (`derivation.md`). A name typed that
way on a phone can't be typed again on a keyboard that doesn't, so the key would be lost to
anyone retyping it from memory. Check on a device; if it happens, turn smart punctuation off
for the name field (UIKit's `smartQuotesType`) or refuse those characters when a name is made.

## Locking with several windows

`UnlockedDiceKeys` is shared by every scene, so on an iPad or Mac with two windows, the
selection in one decides whether the other counts down, and one window going to the
background starts the countdown for both. Fine with one window; worth a per-scene selection
once the Mac target lands.

## Replace upstream's test photos

The scanner should be proved by the owner's own photographs of the owner's own keys, wanted
whether or not the repository is ever published; that those photos can also be
redistributed, and upstream's cannot, is a bonus rather than the reason.

Delete upstream's 23 photos; `Fixtures/images/README.md` says which they are. Most need no
replacement: the owner's photos already cover glare, angle, dim light and fingers; very low
resolution is a downscaled copy of one of the owner's; and the white-box and printed-paper
photos show pre-production keys no one owns. Photograph throwaway test keys for the rest,
each well-framed photo reading at least 20 faces and none misreading:

- A strong shadow across half the key.
- The box turned 180°, as a phone held upside down sees it.
- For `other/`, the lid half closed over the top rows, which must never misread.
- A box mixing dice from two kits, so a letter repeats: every face must read correctly and
  the scan must never finish.
- A finished Stickeys backup, every sticker placed, since restoring from one is scanning it.
- The box held up to a Mac's built-in camera, the one the app uses on a Mac, standing in for
  upstream's crash input.

The corpus totals in `ScannerCorpusTests` then reset to what remains.

## SwiftLint as a build plugin

So Xcode shows violations while editing; CI already runs it.

## Ideas

Not decided, and not commitments. Each records what makes the idea non-obvious, so that
evaluating it later starts from the constraint rather than from scratch.

### Concealing secrets on screen, not just in the snapshot

The privacy cover follows Apple's QA1838: it appears when the app backgrounds, because that
is when UIKit snapshots the scene for the app switcher. A revealed secret and the DiceKey's
grid also hide when the screen is recorded or a screenshot is taken, but the screenshot
itself can't be stopped, and Apple has no app API for more: `privacySensitive()` is applied
by the system only for widgets on the Lock Screen and Always On displays.

The switcher can briefly show a stale snapshot from before the cover was applied, as in other
password managers. The only technique that closes it is putting the content inside a secure
text field's layer, which blocks screenshots, recording and snapshots, but is undocumented
and can break with any iOS release.

### Type only the dice the scanner cannot read

A die with both lines damaged, or one damaged and its text unclear, can never be scanned,
and today that means typing in the whole key. Scanning what it can and asking only for the
rest would save typing 24 dice to fix one.

It looks cheap: the scanner knows which slots it has read and never guesses at the others,
and manual entry already holds a key of partially entered faces (`TypedDiceKey`,
`PartialFace`). Handing the scanned faces over would leave the user only the gaps.

Settle first that a typed face has no second line to check it against, so the screen should
make plain which dice were typed. And scanned rotations are relative to the top of the key as
the camera saw it, so the partial key has to be shown that way up for typed rotations to
agree with it.
