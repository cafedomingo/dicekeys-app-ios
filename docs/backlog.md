# Backlog

Work left to do, roughly in the order it is worth doing, each item large enough for its own
change. The Ideas at the end are questions rather than plans.

## Reveal, Copy and Share on a device

The scanner, its rotations and the keychain prompts have been checked on an iPhone; these
have not.

## Check iCloud sync across two devices

It is built (Settings, Sync with iCloud) and signed for the container, but has only been
opened, never synced between devices. Before shipping, deploy the CloudKit schema to
production in the CloudKit console.

## Names typed with smart punctuation

iOS keyboards may turn `'` into `’` and `--` into `—` even with autocorrection off, and a
key's name is part of its recipe, where `'` is not `’` (`derivation.md`). A name typed that
way on a phone can't be typed again on a keyboard that doesn't, so the key would be lost to
anyone retyping it from memory. Check on a device; if it happens, turn smart punctuation off
for the name field (UIKit's `smartQuotesType`) or refuse those characters when a name is made.

## The Mac

The app is built for the Mac with Mac Catalyst, in the iPad layout: put a team id in
`Config/Signing.local.xcconfig` and run on My Mac (Mac Catalyst) once from Xcode, which
registers the Mac. Run as Designed for iPad instead, macOS reported every camera as upright
at 0 degrees though each needed its own turn, listed a USB webcam nowhere, and zoomed a
Continuity Camera too far, so it is not offered. `scripts/testflight.sh` uploads the Mac
build alongside the iOS one. A Mac-style layout can follow if the iPad look grates. What it
would add, from `design.md`:

- A floating glass sidebar listing DiceKeys with their keys nested beneath, and toolbar
  actions in glass capsules at the top right.
- Scanning with the Mac's camera or Continuity Camera, filling the detail pane.
- Reading a DiceKey on the phone and deriving on the Mac, though a Mac's webcam is a fine
  place to scan too.

In dark mode, `die-box` (`#9fb6bd`, `design.md`) looks too muted on a Mac in daylight.

The app opens one window, as `Info.plist` doesn't set `UIApplicationSupportsMultipleScenes`.
Before it opens more, `UnlockedDiceKeys`, which every scene shares, needs to know which
DiceKey each window has in use and whether every window is in the background: today the last
selection in either window decides which DiceKey the other counts down, and one window going
to the background starts the countdown for both.

## A short written guide

Assembling and backing up a DiceKey, with photographs.

## Rotate the whole app, or nothing

The app is locked to portrait on iPhone while the camera rotates independently, following
gravity through `AVCaptureDevice.RotationCoordinator`. The interface stays still, the picture
inside it turns, and the two disagree about which way is up. Upstream has the same problem.

Decide the model rather than patch the symptoms. Either support interface rotation
everywhere, so the UI and the camera turn together, or lock both to portrait and stop
tracking gravity. The first is more work and the better answer on iPad and Mac, where windows
resize; the second is a deletion. Either way, the key read must still match the physical key
in portrait and both landscapes, as it does today on an iPhone. Check that on a device:
reasoning about the camera's angle convention without hardware was wrong twice.

Rotation never affects derived secrets: `DiceKeySeedTests` proves all four rotations of a key
produce the same seed. Every rotation bug here has been about what the screen shows.

## Passphrase lists as JSON

Move the EFF large wordlist and the two character sets into JSON files the Derivation package
loads as resources, which `scripts/derive-kinds.py` reads too instead of scraping Swift
source. The lists become part of the spec next to `kinds.json`. Changing where they live
changes no key.

## Localization

Every user-facing string is a literal. A String Catalog is the modern form, the project
already sets `LOCALIZATION_PREFERS_STRING_CATALOGS` and `STRING_CATALOG_GENERATE_SYMBOLS`,
and nothing else stands in the way. Sizeable only because there are a lot of strings.

## Replace upstream's test photos

The scanner should be proved by the owner's own photographs of the owner's own keys, wanted
whether or not the repository is ever published; that those photos can also be
redistributed, and upstream's cannot, is a bonus rather than the reason.

Delete upstream's 23 photos; `Fixtures/images/README.md` says which they are.
`scripts/compare-upstream` then compares on the owner's photos alone, and its split by whose
photo it is loses a side. Most need no replacement: the owner's photos already cover glare,
angle, dim light and fingers; very low resolution is a downscaled copy of one of the owner's;
and the white-box and printed-paper photos show pre-production keys no one owns. Photograph
throwaway test keys for the rest, each well-framed photo reading at least 20 faces and none
misreading:

- A strong shadow across half the key.
- The box turned 180°, as a phone held upside down sees it.
- For `other/`, the lid half closed over the top rows, which must never misread.
- A box mixing dice from two kits, so a letter repeats: every face must read correctly and
  the scan must never finish.
- A finished Stickeys backup, every sticker placed, since restoring from one is scanning it.

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

### Shorter exposures on a Mac's camera

In a session of frames saved from a Mac's built-in camera, most frames that fail were blurred
by motion along the bars, so their dots don't decode; no change to the grid recovers them.
A shorter exposure would, if the Mac's camera offers one: check what `AVCaptureDevice` allows
there before designing anything.

### Scanning a Stickeys backup that repeats letters

A backup can repeat letters (`scanning.md`, step 6), but `diceKey` needs 25 different
letters, and step 5's letter check never settles a die whose letter another die shows. Both
are what keep a full sheet of stickers, which repeats five letters, from reading as a key, so
allowing repeats needs another way to tell a backup from a sheet.
