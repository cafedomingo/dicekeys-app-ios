# DiceKey Vault: the specification

**The working plan for the rebuild, removed when it is done.** It turns the idea in
`ROOT-KEY-UTILITY.md` into something to build from, and where the two differ, this wins.
The **Q1**, **Q2** and so on marks point at the decisions at the end. The look is in
`DESIGN.md`; this document covers behavior and bytes.

## What it is

An iPhone and Mac app that regenerates a few rarely used, costly-to-lose keys from a DiceKey:
SSH client and host keys, WireGuard and age keys, a wallet's recovery phrase, and
passphrases for anything that just calls for a password: a NAS's encryption key, an
encrypted backup or disk image, a password manager's master password. The phone is the best
camera for reading the DiceKey, and the Mac is the better place to derive and export, so
both run the same app. It never stores a derived key, has no network code and no AutoFill, and does nothing for
per-site passwords.

**Platforms.** One SwiftUI multiplatform target for iOS 26 and macOS 26 and later, Liquid Glass,
stock components (`NavigationStack` and `TabView` on iPhone, `NavigationSplitView` on Mac).
`Derivation` and `ReadDiceKey` already build for iOS 26 and macOS 26. On Mac the camera is the
built-in one or an iPhone through Continuity Camera, through the same AVFoundation path.

## Credit, and what is replaced

This is a derivation from a DiceKey, the physical object DiceKeys, LLC makes, and the app
says so plainly instead of hiding it: About reads "Reads DiceKeys, made by DiceKeys, LLC",
and the physical object is called a DiceKey wherever the user has to know which box to fetch.
Everything else that came from upstream is replaced where it can be:

- **Name, icon and look.** DiceKey Vault as the working name (**Q12**), its own icon and
  design system, and no DiceKeys illustrations or brand colors. Inconsolata stays for the dice alone, because it is
  the face printed on them, which reverses `ROOT-KEY-UTILITY.md`'s "no Inconsolata". It is OFL
  and stays in `THIRD_PARTY_LICENSES`.
- **Test photos.** The scanner corpus moves entirely to the owner's photographs of the owner's
  keys, as `BACKLOG.md` already plans; upstream's photos are then deleted.
- **Code.** Already rewritten in Swift here; what remains of upstream is the format the
  derivation keeps (below) and the face specification, which describes the physical dice.
- **Setup instructions.** Assembling and backing up a DiceKey move out of the app into a
  short written guide with the owner's photographs.

## The derivation

### Keep the DiceKeys construction, with fixed recipes (Q1)

Two ways to build it were weighed.

| | Keep the construction, fixed recipes | New HKDF-SHA256, as `ROOT-KEY-UTILITY.md` proposed |
|---|---|---|
| Hash | keyed BLAKE2b, the 183-line `BLAKE2b.swift` already here and tested against RFC 7693 | CryptoKit's `HKDF<SHA256>` |
| Salt | a recipe string from a template this app writes; no free-form recipes | a domain string, and a length-prefixed kind and name |
| Proven by | the 168 vectors recorded from the reference C++, plus new vectors for the encodings | new vectors only, from Swift and an independent script |
| If this app dies | any DiceKeys app that takes a raw recipe, or seeded-crypto, derives the same bytes; the encodings below turn them into keys | the spec and the script |
| DiceKey ids | unchanged, so saved DiceKeys keep their identity | all change |
| Deleted either way | free-form recipes, templates, raw JSON, OpenPGP, the emoji list and unused character sets | the same, plus BLAKE2, the parser and the reference vectors |

**Recommendation: keep the construction.** What made the old derivation complex was
everything a user could put in a recipe. Once every recipe comes from a template this app
writes, most of that complexity goes either way. What is left to pay for compatibility is
183 lines of BLAKE2b that already exist, and Python's standard library has keyed BLAKE2b
(`hashlib.blake2b(key=…, digest_size=32)`), so an independent implementation is just as
short. In exchange, other implementations exist and can stand in, and the reference vectors
keep guarding the core. A rewrite would trade both of those for 183 lines.

"Compatible" here means only this: the bytes for each key are what the DiceKeys format gives
for its recipe. The DiceKeys apps cannot show an age or WireGuard key, or this app's
passphrase format, but they show the derived bytes (`unsealingKeyBytes`, `secretBytes`) and
the encodings below are a few lines from there.

### The seed and the construction (unchanged)

As `derivation.md` describes: the seed is the DiceKey's 75-character human-readable form,
rotated to whichever of its four rotations sorts first. The bytes are HKDF over keyed BLAKE2b
with a zero salt, where `info` is the type string followed by the recipe text. The X25519
scalar is the first 32 bytes of SHA-512 of the derived bytes, unclamped, and the Ed25519 seed
is the derived bytes.

### Kinds

Each kind is one DiceKeys type and one recipe template. `<name>` is the entry's name as a
JSON string body: `"` and `\` escaped with a backslash, nothing else escaped, so non-ASCII is
written raw.

| Kind | Type | Recipe |
|---|---|---|
| SSH | SigningKey | `{"purpose":"ssh:<name>"}` |
| WireGuard | UnsealingKey | `{"purpose":"wireguard:<name>"}` |
| age | UnsealingKey | `{"purpose":"age:<name>"}` |
| Passphrase | Password | one of the generator's templates, below |
| Wallet | Secret | `{"purpose":"wallet:<name>"}` |
| DiceKey id | Secret | `{"purpose":"a unique identifier for this DiceKey","lengthInBytes":16}`, as now |

The kind prefix keeps apart two kinds that share a type, or that could share one later, so a
WireGuard key and an age key with the same name are unrelated (**Q2**). Every template is
written as RFC 8785 (JCS) canonical JSON, every field sorted by UTF-16 code unit, since these
recipes are new and only this app writes them. The DiceKey id recipe alone keeps the
reference's text, so ids match the DiceKeys apps.

**SSH client and host keys are one kind** (**Q3**): a host key is an SSH key named for the
host. The format is the same, and a derived host key is what lets a rebuilt server keep its
identity.

### The name

These rules are exact, so the Python script can match them:

- **Trimming.** Remove, from both ends, the code points with the Unicode `White_Space`
  property (U+0009 to U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000 to U+200A, U+2028,
  U+2029, U+202F, U+205F, U+3000). Then normalize to NFC. Otherwise the name is kept exactly
  as typed, case included, because one changed character is a different key.
- **Length.** 1 to 64 Unicode scalar values after trimming and normalizing.
- **Refused.** General category `Cc` (U+0000 to U+001F and U+007F to U+009F) (**Q4**).
- **Public.** The name is stored in the catalog and shown on screen.
- **Several keys of a kind** means several names. Rotating a key means a new name.

### Encodings

| Kind | Secret | Public | Checked against |
|---|---|---|---|
| SSH | unencrypted `openssh-key-v1`, as `KeyFormats.OpenSSH` writes it now, with the name as its comment | `ssh-ed25519 <base64> <name>` | `ssh-keygen -y` |
| WireGuard | base64 of the 32-byte scalar | base64 of the X25519 public key | `wg pubkey` |
| age | `AGE-SECRET-KEY-1…`: Bech32 of the scalar with HRP `age-secret-key-`, checksum over the lower case string, then the whole string upper-cased | `age1…`: Bech32 of the public key with HRP `age` | `age-keygen -y` |
| Passphrase | the derived password, as the formatter joins it | none | `extensions.json` and the Python script |
| Wallet | 24-word BIP39 English phrase from the 32 bytes, no BIP39 passphrase | none | BIP39's published vectors |

**SSH comments.** Today `OpenSSH.publicKeyLine` hard-codes `DiceKeys`, and
`privateKeyPEM(comment:)` defaults to an empty comment. Both take the entry's name instead.
No key bytes change, and `authorized_keys` then says which key a line is.

**Clamping.** WireGuard clamps a private key in `generate_public`, age clamps through
`golang.org/x/crypto/curve25519`, and CryptoKit clamps when it computes the public key. So
the unclamped scalar gives the same public key in all three. Confirm that with `wg pubkey` and
`age-keygen -y` before building anything else on it. `wg show` may display the clamped form of
the private key rather than the string that was entered; that is expected. age needs a Bech32
encoder, about 40 lines.

### The passphrase

The Passphrase kind is the generic one: whatever asks for a password, rather than a key of a
particular format, gets a passphrase under its own name ("nas", "backup disk", "1password").
It is not a password manager. These are a few passphrases you need rarely and can't afford
to lose, and none is stored.

It keeps the generator from #32, cut down to two styles (**Q5**). Its settings are part of
the recipe, so they are part of the key, like the name. The catalog entry records them, and
changing one makes a different passphrase. The New key draft shows them with #32's live
preview and strength bar.

| Style | Recipe | Settings | Default |
|---|---|---|---|
| Random | `{"lengthInChars":<n>,"purpose":"passphrase:<name>","wordList":"<set>"}` | length 12 to 64; "Include symbols" chooses `CHARS_67_letters_digits_symbols_20261002` over `CHARS_57_letters_digits_20261002` | 24 letters and digits, about 140 bits |
| Memorable | `{"lengthInWords":<n>,"purpose":"passphrase:<name>","separator":"<sep>","wordList":"EFF_large_7776_words_9_chars_max_20160719"}`, with `"capitalize":true` first when "Add a digit and a capital" is on | 4 to 10 words; that toggle sets `separator` to `digits` instead of `-` | 6 words joined by hyphens, about 77 bits |

Both templates are this app's extensions to the format (`recipe-format.md`), pinned by
`extensions.json`. The DiceKeys apps cannot reproduce a passphrase, only the bytes behind it.

- **Character sets.** Letters without `I`, `O` and `l`, and digits without `0` and `1`,
  because these get typed by hand. In order, that is `ABCDEFGHJKLMNPQRSTUVWXYZ`, then
  `abcdefghijkmnopqrstuvwxyz`, then `23456789`. With symbols, `!@#$%&*-_?` follows.
- **It works on Synology.** No setting produces `=`, `,` or `:`, the characters Synology's
  shared folder encryption key refuses (DSM 7 help, "Create a Shared Folder"). Synology
  documents no length limit for that key; its account passwords allow up to 127 characters.
  Hyper Backup documents neither, so neither is tied to Synology beyond avoiding those three.
- **Shells.** Letters, digits and hyphens need no quoting. With symbols on, a passphrase
  typed into a shell needs single quotes.
- **Composition is not forced.** Random letters and digits at 24 characters has no digit
  about 2.7% of the time. Memorable with "Add a digit and a capital" always has both.
  Nothing retries for a composition rule, so the format stays one rule per character.
- **Off the list.** The emoji list, PINs, letters only, letters with symbols, and the two
  reference word lists are no longer offered.

### The DiceKey id

Unchanged: the 16-byte Secret above, written as URL-safe base64 without padding. It keys
saved DiceKeys and catalog entries, it reveals nothing about the DiceKey, and it is how a
scan is recognized.

### Proving it

- `vectors.json` stays whole: all 168 cases, recorded from the reference C++. The 98
  Password cases need the reference word lists and the recipe parser, and both stay in the
  package for that reason, although the app no longer offers either list.
- `extensions.json` keeps the cases for the lists still offered, and drops the cases for the
  lists removed.
- A new fixture, `kinds.json`, gives each kind's encoded output for the fixture DiceKeys and a
  handful of names, chosen to include non-ASCII, quotes, trimmed spaces and the length limit.
- CI derives `kinds.json` twice: once in Swift, and once in a short independent Python script.
  The script uses standard library `hashlib.blake2b(key=…, digest_size=32)`, `cryptography`
  for the curves, and the word list files. Keyed BLAKE2b in Python reproduces all 38 Secret
  cases in `vectors.json`. The public keys are checked once against `ssh-keygen -y`,
  `wg pubkey` and `age-keygen -y`, and the wallet against BIP39's vectors.
- Any change to a derived byte stays a bug, as `ARCHITECTURE.md` goal 1 says.

### What `Derivation` keeps and loses

**Keeps.** The construction (`BLAKE2b`, `HKDF`, `Engine`, `HashFunction`) and the recipe
parser with its errors (`Recipe`, `RecipeJson`, `DerivationError`), because `Engine`,
`Derived`'s three key types and the Password cases all take a `Recipe`. It also keeps
`Derived`, `DerivableType`, the password formatter and joining, `WordList` with the two
reference lists, EFF and the two character sets above, and from `KeyFormats`, `OpenSSH`,
`BIP39`, `Armor` and `ByteWriter`.

**Loses.**

- `OpenPGP`, and the code only it used (`Armor.crc24` and its `crc:` parameter,
  `ByteWriter.mpi` and `uint16`)
- the emoji list
- the letters-only, letters-and-symbols and PIN character sets

**Gains.** The kind templates, Bech32, and a `comment` parameter on `OpenSSH.publicKeyLine`.

On the app side, the recipe list, templates, the custom recipe and raw JSON sheets, the
sequence number field and the QR code sheet all go.

**Not yet.** A Secret-only derivation, with the parser reduced to the templates, would be a
later simplification. It would cost the 98 Password vectors, and it is not needed for the
rebuild. The Argon2id and seeding-implementation items in `BACKLOG.md` close, and simpler
recipes is answered by the templates.

## The scanner

`ReadDiceKey` stays as it is: the generated face specification and the Swift scanner. Two
things are outstanding regardless of this rebuild. It has not yet run on a device, and every
key depends on reading the DiceKey right, so that comes first. Its corpus also has to move to
the owner's photographs. Manual entry stays as the fallback.

## The app

### What is stored

- **A DiceKey**, by id: a name, defaulting to "DiceKey with M1 in center" from its center die,
  as the current app does; the center face, for its avatar; and optionally the DiceKey itself
  in the keychain, behind user presence and `WhenUnlockedThisDeviceOnly`, as now.
- **A catalog entry**: the DiceKey id, the kind, the name, the public key where the kind has
  one, and the date made. Nothing in it is secret.
- **Never** a derived secret.

### The catalog file

Export and import use one small versioned JSON file:
`{"v":1,"diceKeys":[{"id","name","center"}],"entries":[{"diceKey","kind","name","publicKey","made"}]}`.
An import merges by DiceKey id plus kind plus name. The **paper copy** is a printable page:
the DiceKeys and their entries listed as text, and the same file as a QR code, meant to be
kept in the box. Whoever holds the box already holds every key, so the list costs nothing
there, and recovery then needs only the box.

### iCloud sync (an option)

With sync on, the catalog lives in the user's CloudKit private database, so iPhone and Mac
show the same DiceKeys and entries. What syncs is the catalog alone: DiceKey ids, names and
center faces, and for each entry its kind, name, passphrase settings, public key and date.
That is everything needed to rebuild each recipe, and nothing that unlocks one.

- **The DiceKey itself never syncs.** The optional keychain copy is
  `WhenUnlockedThisDeviceOnly`, so each device has to scan the DiceKey (or keep its own
  keychain copy).
- **Matching is by id.** Every scan derives the DiceKey id from the dice, and the id selects
  that DiceKey's catalog entries, on any device. The id is a one-way derivation and
  reveals nothing about the dice. A misread die or the wrong box derives a different id and
  shows as a new DiceKey.
- **Merging** is by DiceKey id plus kind plus name, as for an import. An entry is never
  edited, only added or deleted, so conflicts reduce to deletes.
- **What Apple holds** is that metadata: the existence of an entry named "wallet: cold", but not
  the wallet. Advanced Data Protection makes it end-to-end encrypted.
- **Default.** Sync is offered on first launch and can be turned off in settings; export and
  the paper copy work either way.

### Why keys carry no verify state

A key's public half is recorded in its entry, but it is never checked again. The name is
stored, and an import from the file or the QR code is exact, so the same DiceKey always
derives the same key. A name typed back in from the paper list is the one way a mismatch can
slip in. For that case, the paper copy prints each entry's fingerprint, and the New key draft
shows the fingerprint live, so the two can be compared before saving.

### Unlocking

Scanning or typing a DiceKey unlocks it in memory. The current app expires it 59 seconds
after you leave its screen, with a menu to extend the time; whether that default carries over
is **Q7**. A scan is recognized by its id: a known DiceKey opens with its name and keys, and
an unknown one shows the "New DiceKey" notice with Scan again, which is how a misread die or
the wrong box shows up. Keys have no verify state of their own.

### Screens

These are designed in the design system:

- Load (camera)
- A DiceKey, known and new
- Keys
- A key
- New key, as a live draft
- Mac sidebar, detail and scan

These still need designs:

- **Type it in.** Manual entry: a 5×5 grid and a die keyboard.
- **Reveal, per kind.** The SSH and age file export. The 24-word wallet, numbered in columns
  and never copyable as one string (**Q8**). The passphrase in its groups.
- **The paper copy**, and import.
- **Forget this DiceKey**, a confirmation sheet.
- **Rename a DiceKey.**
- **About.**

### Getting a key off the device

In order of preference:

1. The public key, copied or shared.
2. A file through the share sheet or AirDrop, for SSH and age identities.
3. The clipboard, for passphrases: local only, expiring after one minute, as now.
4. Running the app on the Mac and deriving there.

There is no network transport and no SSH agent.

### Concealment

The app shows a plain cover in the app switcher snapshot (no mesh), conceals revealed
secrets again when it moves to the background, and offers no screenshots of a revealed
secret where the platform allows it.

## Naming

The bundle identifier stays `com.cafedomingo.dicekeys`, this fork's own (`Signing.xcconfig`),
so TestFlight history and saved keychain items carry over. Only the `com.dicekeys` prefix in
`project.yml`, which belongs to DiceKeys, LLC, should go. The working name is DiceKey
Vault: "DiceKey" names the object it works with, and About credits DiceKeys, LLC so it isn't
mistaken for their app. "Vault" usually means a store of secrets, and this app stores none,
so the name is open until release (**Q12**). The scheme, the `DiceKeys/` source folder and the repository can keep their names.

## Order of work

1. The target: add a macOS destination to `project.yml`, keeping the deployment target at 26. Drop the `network.client` and photo library
   entitlements, since nothing uses the network and nothing picks photos.
2. Run the scanner on a device and replace the corpus.
3. The derivation: the kind templates, the encodings, `kinds.json` and the Python script.
   Confirm the age and WireGuard public keys against the real tools first.
4. Delete what `Derivation` loses.
5. The catalog, unlock and recognition.
6. The new UI, iPhone and Mac together, from the design system.
7. Delete the old screens, flows and illustrations.
8. The display name, and the written guide.

## Decisions

1. Keep the DiceKeys construction with fixed recipes.
2. A kind prefix in `purpose`, as in `ssh:github`.
3. One SSH kind for clients and hosts.
4. Names of 1 to 64 Unicode scalar values, with no `Cc` control characters.
5. Passphrases from #32's generator, cut down to Random and Memorable.
6. iCloud sync of the catalog, as an option.
7. The 59-second expiry on iPhone; on Mac, expiry when the window closes or the screen
   locks.
8. The wallet phrase is shown to be written down, never copied as one string.
9. No BIP39 passphrase.
10. One target for iPhone and Mac, with the same screens.
11. Throwaway DiceKeys only, in fixtures and photos.
12. DiceKey Vault is the working name; the release name is still open. The bundle
    identifier stays.
