# A root-key utility rather than a password manager

**Not decided**, and listed under Ideas in `BACKLOG.md`. It would remove most of the app,
replace the derivation, and change how the app is used. As a password manager the app loses
to a real one on every daily measure: no AutoFill, no sync, and a box of dice to fetch first.
What a DiceKey uniquely gives is a root secret that lives offline and regenerates other
secrets on demand. That suits secrets touched rarely and costly to lose, so the app would be
where those are rebuilt from, never where they are used.

**Who it is for.** The owner, using their own DiceKeys for things they actually need. If
others find it useful, good, but no one is owed compatibility, the owner included: nothing
derived today has to keep working.

**What it would be for.** The owner's actual uses, and nothing else:

- SSH keys, for clients and for server hosts, where a derived host key lets a rebuilt server
  keep its identity so `known_hosts` never objects;
- WireGuard keys;
- the encryption passphrase for a Synology NAS;
- one password, the password manager's master password;
- a cryptocurrency wallet seed, as a BIP39 recovery phrase;
- possibly an age identity for encrypting backups. [age](https://age-encryption.org) is a
  small file encryption tool and format, a modern stand-in for encrypting files with GPG: a
  key is one line of text, and a file is encrypted to its public half. It matters only if
  backups are encrypted with age itself; a tool that takes a passphrase, such as Hyper
  Backup, wants a passphrase instead.

Per-site passwords are not on the list, and they are what most of the app is built around.

## A clean break

**Minimal, and the owner's own.** A new name, a new icon, and nothing of DiceKeys' look: no
illustrations, no brand colors, no Inconsolata, no privacy-cover mesh. System font, system
tint, stock controls, plain backgrounds, and a DiceKey drawn, where it has to be drawn at all,
as a grid of letters, digits and orientations. The only credit is to the hardware: an About
line saying the app reads DiceKeys, made by DiceKeys, LLC, and calling the physical object a
DiceKey wherever the user has to know which box to fetch.

**Renaming touches more than the display name.** The app, the scheme, the `DiceKeys/` source
folder, the `com.dicekeys` prefix in `project.yml`, the repository and the docs all carry the
name. The bundle identifier is the expensive one: a new identifier is a new App Store Connect
record, so TestFlight history and the keychain items saved under the old one stay behind.
Nothing has to stay compatible, so that is acceptable, and doing it once, with the new
derivation, beats doing it twice.

**Written for this app, not inherited.** No existing behavior binds the new one. Upstream's
code is a reference for how something was once done, never a constraint on how it is done
now: the DiceKey model, its seed encoding, the screens and the catalog are designed from this
app's needs and written fresh rather than edited into shape. Where something already serves
well, it stays on its merits: the scanner and the face specification read a DiceKey
correctly, are already Swift written here, and change only where the new app needs them to.
Licensing is not a goal of the break; `THIRD_PARTY_LICENSES` keeps crediting whatever
remains, as now.

## A new derivation

Leaving the DiceKeys ecosystem is what makes the rest simple. The current derivation exists
to match the other DiceKeys apps byte for byte: a custom HKDF over BLAKE2b, JSON recipes
whose exact text is the salt, a canonical form that follows the reference rather than RFC
8785, five word lists and a dozen length options. None of that serves the uses above.

**The construction.** HKDF-SHA256 (RFC 5869, `HKDF<SHA256>` in CryptoKit) with:

- input key material: the 25 dice as a byte encoding of this spec's own, each die's letter,
  digit and orientation in reading order, taken from whichever of the four rotations sorts
  first, so every way of holding the key still derives the same values;
- salt: one fixed, versioned domain string, the only place a version lives;
- info: the kind and the name, each length-prefixed, so no two inputs encode alike and
  there is no text format to canonicalize;
- output: 32 bytes for every kind but the passphrase, which reads as many as it needs.

No stretching: a DiceKey carries about 196 bits of entropy, so a slow hash such as Argon2id
adds nothing, which also answers the Argon2id idea in `BACKLOG.md`.

**One output per kind, with no options.**

| Kind | From the derived bytes | Checked against |
|---|---|---|
| SSH, client or host | Ed25519 seed, OpenSSH format | `ssh-keygen -y` |
| WireGuard | X25519 private key directly, base64 | `wg pubkey` |
| age | X25519 private key directly, bech32 | `age-keygen -y` |
| Passphrase | a fixed number of characters from one fixed alphabet | the Python script |
| Wallet | 24-word BIP39 recovery phrase from 32 bytes | BIP39's published vectors |

**The passphrase.** Characters rather than words: upper and lower case letters and digits,
less the look-alikes `0 O 1 l I`, since these passphrases get typed by hand, and a small
fixed set of symbols that need no quoting in a shell or escaping in a URL. About 65
characters, so 22 of them is about 132 bits. Carrying all of the DiceKey's 196 would take 33,
and gain nothing: 128 bits is past any brute force, the SSH, WireGuard and age keys stop at
about 128 bits of security themselves, and a passphrase that leaks reveals nothing about the
DiceKey or its other keys whatever its length. Each character comes from one derived byte by
rejection sampling, so none is likelier than another, and a finished string missing any of
the four classes is thrown away for the next one from the same output, so every passphrase
passes the usual composition rules. Nothing like `lengthInChars` or a choice of alphabet:
the alphabet, the symbols and the length are fixed once and can never change, so Synology's
limits on length and characters have to be known before they are.

**SSH.** Ed25519 only, as now: the private key in OpenSSH's own `openssh-key-v1` format,
the only one OpenSSH writes for Ed25519, and the public key as an `ssh-ed25519` line. The
comment becomes the entry's name, in both, so `authorized_keys` says which key a line is;
today it is a fixed `DiceKeys`. No choice of key type: RSA has no standard way to be derived
from a seed, and ECDSA would be added only if a device that has to be reached turns out to
refuse Ed25519. A possible extension, not part of the first version: a passphrase on the
exported file, typed at export time, since that file is what sits in Downloads. It needs
bcrypt_pbkdf, which CryptoKit lacks, so it is not free.

**The wallet.** BIP39 is the format wallets import, and `KeyFormats` already encodes it with
the English list, so it costs nothing. It does put a wallet's master secret on a phone's
screen, which is the exposure hardware wallets exist to avoid; it suits a wallet the DiceKey
backs up and restores, not one used from the phone.

**The name.** A free text field, and the only way to get more than one key of a kind:
`nas` and `nas backup` are two passphrases, `github` and `homelab` two SSH keys. Rotating a
key is a new name. The name is the salt, so one changed character is a different key; it is
trimmed and normalized to NFC before hashing, and otherwise kept exactly as typed, case
included. It is public, saved in the catalog below, and shown on screen.

**Proving it without a reference.** Today's derivation is proved by vectors recorded from
the reference C++. A new one has no reference, so the spec has to be complete enough to
reimplement from, and CI should derive the vectors twice: once in Swift, once in a short
independent script (Python's standard library has HKDF's pieces and Ed25519 is one package
away). If the fork dies, the spec and that script are how the keys come back.

**What changes in the rules.** Goal 1 in `ARCHITECTURE.md` becomes "re-derive the same
secrets as the spec" rather than "as the reference", and the rule that any change to a
derived byte is a bug carries over to the new construction unchanged. Every value derived
today changes, deliberately: there is no migration, and the current engine is deleted rather
than kept alongside. The other DiceKeys apps stop being a fallback, which is why the spec and
its independent script matter.

**What it deletes.** The BLAKE2 target, the BLAKE2b HKDF, JSON recipes and their
canonicalizer, `recipe-format.md`, `recipe-schema.json`, the password formatter,
every word list but BIP39's English one, OpenPGP, and in the end `vectors.json`. The open questions about
Argon2id, the seeding implementation and simpler recipes in `BACKLOG.md` all go with them.

## The app around it

**Verify without revealing.** Re-derive and show only the public key or a fingerprint, and
compare it with the one recorded when the key was made. That is a recovery drill which shows
nothing secret, and a check on the scanner as well.

**A catalog, not recipes.** Making a key saves an entry: the kind, the name, which DiceKey
it belongs to and, where there is one, the public key. Retrieving it later is picking the
entry and unlocking the DiceKey, and the key is derived again; the key itself is never saved.
None of the entry is secret, so it can be stored freely, and creating one is a choice of kind
and a text field. Recovering after losing the phone needs the box and the names, so names
should be ones that could be typed again from memory, and the catalog can be exported or
synced, since it holds nothing that unlocks anything. The sturdiest export is on paper, kept
in the box: whoever holds the box already holds every key, so the list costs nothing there,
and recovery then needs only the box.

Exporting implies importing, so the format is a small versioned file of its own, read back
on a new phone or merged into an existing catalog, with the paper copy carrying it as a QR
code beside the readable list so it can be scanned rather than typed. An imported entry keeps
its public key, so the first unlock of its DiceKey re-derives each key and compares: a
mismatch means a mistyped name or the wrong DiceKey, caught before the key is needed.

**Getting a key off the phone.** Exports are rare, once to provision and once after a
disaster, so they can be deliberate rather than convenient. In order of preference:

- the public key only, for `authorized_keys`, a WireGuard peer or an age recipient, so
  nothing secret moves;
- AirDrop or the share sheet, as a file, for an identity going to one's own Mac, at the cost
  of a file left in Downloads (the QR code sheet item in `BACKLOG.md` already asks whether
  this beats QR);
- the clipboard, as now, local only with a one-minute expiry, for passphrases;
- the app itself on the Mac, as in the iPad and Mac item in `BACKLOG.md`, deriving there
  rather than moving the key, on a more exposed machine.

Not a network transport or an SSH agent: large, and easy to get wrong.

**Several DiceKeys.** The memory store already holds more than one unlocked DiceKey, keyed
by `DiceKey.id`, and that stays: each catalog entry belongs to one DiceKey, and the catalog
shows a DiceKey's entries whether or not it is unlocked. The id is itself a derived value,
16 bytes from the current engine, so it moves to the new construction as a kind of its own,
and every saved DiceKey and entry is keyed afresh. It reveals nothing about the key, and the
same name under two DiceKeys is two unrelated keys.

## Screens

The app shrinks to loading a DiceKey and working with its keys. Setup, meaning assembling a
DiceKey and copying it to a backup, moves out of the app into a written guide.

**What remains.**

- **Home.** Saved and unlocked DiceKeys, and Load. The Assemble entry goes.
- **Load.** Scan or type, as now. Scanning a DiceKey that differs from one already loaded in
  only a few dice highlights those dice, which is all that survives of validating a backup:
  copy the key, load the original, scan the copy.
- **A DiceKey.** Two tabs rather than three: the key itself, with saving to the keychain and
  the expiry as now, and its keys, the catalog entries for this DiceKey. The Backup tab goes.
- **New key.** A kind and a name, nothing else.
- **A key.** Its name, kind and public key or fingerprint, whether it verified on this
  unlock, and the deliberate actions: reveal, copy, share as a file.
- **Catalog import and export**, including the paper copy with its QR code.

**What goes.** The assembly walkthrough and its illustrations; the backup flows, Stickeys and
a second DiceKey kit, with their sticker sheets, die-by-die transfer steps and progress; the
recipe list, templates, custom recipe form, raw JSON view and sequence number field; the QR
code sheet for derived values, which none of the export paths above needs. Raw JSON and web
address recipes go with them, and the AutoFill idea is the opposite bet, so choosing one
rules out the other.

**The guide.** Upstream never published these instructions anywhere but inside its apps; the
DiceKeys FAQ covers only reopening a box sealed too early. So the guide is written here, short
and with photographs rather than the app's illustrations:

- assembling: shake the dice, let them fall into the base, place the stragglers without
  turning them, load the DiceKey in the app before sealing, so a die the scanner cannot read
  is found while the box is still open, then line up the hinges and press the top on;
- backing up: a Stickeys sheet or a second kit, copied die by die with the same letter, digit
  and orientation in the same place, then checked by scanning it as above;
- what to keep where: the box, the backup apart from it, and the catalog's paper copy in the
  box;
- a recovery drill: load the DiceKey now and then and let verify confirm every key.

**Before starting.** The rewritten scanner has not run on a device, and every output depends
on reading the key right. A phone is also a worse place for a root secret than an offline
machine; the answer is that the key is loaded rarely and briefly, which the expiry already
enforces. The order would be the spec and its two implementations first, replacing the current
engine outright, then the catalog and verify, then the removals.
