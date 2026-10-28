# Several algorithms per key

## Why

An age key derives two identities from one recipe: X25519 and ML-KEM-768 + X25519
(post-quantum). #47 built that as a special case: `DerivedKey.postQuantum`, an
`AgeRecipient` enum on the key screen, a `postQuantum` object in `kinds.json`, and a
catalog that held only the X25519 recipient, so the post-quantum one showed only while the
DiceKey was unlocked (#69). #68 fixed that bug with one more special case,
`KeyEntry.postQuantumPublicKey`.

The owner wants the general version instead. A kind can derive more than one algorithm
from one recipe; post-quantum age is the first, post-quantum SSH is expected later, and
people have long wanted "the same key type, another algorithm" (RSA beside Ed25519 is the
familiar example, though RSA is not wanted here). Adding an algorithm to a kind later
should be a small, additive change that never breaks a newer app reading what an older one
wrote.

This replaces #68, which should be closed unmerged once this lands.

## Goals

- A kind declares an ordered list of the algorithms it derives. Every key of that kind
  derives all of them, from its one recipe. The user picks which to use; nothing is chosen
  at creation.
- The order is the emphasis: the first is shown first. Reordering later (say post-quantum
  first, X25519 de-emphasized but still derived) changes no stored data.
- Every derived public key is recorded in the catalog, so it shows whether or not the
  DiceKey is unlocked, and every derived public key is exported.
- Default keys travel in the export file and on paper like any other key, so a later app
  can make one again from them.
- Adding an algorithm to an existing kind later needs no recipe change, no format change and
  no migration: existing entries fill it in when their DiceKey is next unlocked.

## Non-goals

- RSA, or any new algorithm. Today's set is unchanged: ssh Ed25519; wireguard X25519; age
  X25519 and ML-KEM-768 + X25519.
- Choosing an algorithm when a key is made, or recording a choice in the recipe.
- A Reveal per algorithm. Reveal shows every secret of the key at once, as now.
- Changing which algorithm is emphasized. Age keeps X25519 first.

## Anti-goals

- Any change to a derived byte. Every value in `kinds.json` stays byte-identical; only the
  file's shape changes.
- An algorithm-specific field, type or branch where a list would do (`postQuantum`,
  `postQuantumPublicKey`, `kind == .age` checks for a second key).
- Once the app has shipped, a newer app failing to read, or silently losing, anything an
  older one wrote.

## Compatibility rules (the owner's)

- **Nothing has shipped yet, so nothing needs to stay compatible with what came before.**
  This change rewrites the file and paper formats and their fixtures freely; what it
  produces becomes the first pinned form. The rules below apply from the first release on.
- **Newer app reading older data must never break or lose anything.** Old stores, old
  export files and old paper must all still load fully.
- **Older app reading newer data** only needs to warn. Older builds already do: an import
  says "N keys couldn't be read." No version bump to force a clearer message.
- **`publicKey` is dropped**, from the store, the file's writer and the file's reader, with
  no migration of its values. Its values are derivable, and the fill writes them again on
  the next unlock.

## How it works (decided)

### Algorithms are derivation types

Each algorithm is a `DerivableType` (`ed25519`, `x25519`, `mlkem768x25519`, `passphrase`,
`bip39`). The type is already hashed in front of the recipe (`info = type || recipe`), so:

- two algorithms of one kind derive independent bytes from the same recipe;
- adding an algorithm never changes an existing key;
- the type's raw value is already frozen forever, so it is the algorithm's stored name.

Within one kind, each algorithm has a distinct type (it must: the same type would derive
the same bytes). The same type may appear in different kinds (`x25519` in wireguard and
age), encoded differently per kind.

### The data structures

**`KeyKind` (Derivation)** gains the ordered list. Passphrase and wallet are one algorithm
with no public half, so every kind goes through the same path.

```swift
// before
public var hasPublicKey: Bool            // ssh, wireguard, age

// after
public var hasPublicKey: Bool            // unchanged
/// Every algorithm a key of this kind derives, from its one recipe, in the order shown.
/// Append only: an algorithm, once released, is never removed, reordered out or retyped.
public var algorithms: [DerivableType] {
    switch self {
    case .ssh: [.ed25519]
    case .wireguard: [.x25519]
    case .age: [.x25519, .mlkem768x25519]
    case .passphrase: [.passphrase]
    case .wallet: [.bip39]
    }
}
```

("Append only" is about the set. Reordering for emphasis is allowed, since nothing stored
depends on order.)

**`DerivedKey` (KeyFormats)** holds one entry per algorithm instead of one key plus an
optional second.

```swift
// before
public struct DerivedKey {
    public let recipe: KeyRecipe
    public let publicKey: String?
    public let fingerprint: String?
    public let secret: String
    public private(set) var postQuantum: AgePostQuantumKey?   // recipient, identity
}

// after
public struct DerivedKey {
    public let recipe: KeyRecipe
    /// One per algorithm of the recipe's kind, in `KeyKind.algorithms` order.
    public let algorithms: [AlgorithmKey]

    /// For the catalog: each public key by its type's raw value.
    public var publicKeys: [String: String]
}

public struct AlgorithmKey: Equatable, Sendable {
    public let type: DerivableType
    /// `authorized_keys` line, WireGuard key, age recipient. Nil for passphrase and wallet.
    public let publicKey: String?
    /// Short form to compare by eye. Nil when there is no public key.
    public let fingerprint: String?
    /// Private key file or string, passphrase, or recovery phrase.
    public let secret: String
}
```

`AgePostQuantumKey` goes away; `Age.postQuantum(seed:)` returns what the age case needs
to build its second `AlgorithmKey`.

**`KeyEntry` (catalog, SwiftData)**

```swift
// before (main)
@Model final class KeyEntry {
    var diceKeyID = ""
    var recipeJSON = ""
    var publicKey: String?          // X25519 only, for age
    var created = Date.now
}

// after
@Model final class KeyEntry {
    var diceKeyID = ""
    var recipeJSON = ""
    /// Each algorithm's public key, by its type's raw value:
    /// ["x25519": "age1…", "mlkem768x25519": "age1pq1…"].
    /// Keyed by String, not DerivableType, so a name this version doesn't know (from a
    /// newer version on another device) is kept when this version writes, not dropped.
    /// Never filter on it in a #Predicate: SwiftData crashes (see Spike).
    var publicKeys: [String: String] = [:]
    var created = Date.now

    /// Its kind has a public half and some algorithm's public key is missing.
    var needsPublicKey: Bool
}
```

- The fill (`fillPublicKeys`) sets each missing algorithm's entry one by one, never
  replacing the whole map, so unknown names survive.
- `ContentView`'s fill trigger can't filter on the map, so it queries every `KeyEntry` and
  checks in code: first whether the entry's DiceKey is unlocked (cheap), then
  `needsPublicKey` (decodes the recipe). Nothing caps the store's rows, so keep the cheap
  check first.
- `CompatibilityTests.storeAttributes` drops `publicKey` and pins
  `"publicKeys": "Dictionary<String, String>"` (the spike's `valueType`).
- **CloudKit (decided: keep the dictionary, gated by a device check).** Sync can't be
  tested in CI (tests open the store with `syncing: false`). Before the PR merges, the owner
  installs a build of the branch, turns on Sync with iCloud, and confirms Settings shows no
  sync failure (`DiceKeyVaultApp.syncFailure`, set when the synced store fails to open and
  the app falls back to this device's copy) and that public keys show after an unlock. If
  the synced store won't open with the dictionary, the fallback is a String column
  `publicKeysJSON` holding the same map as JSON, decoded and merged key by key, pinned as
  `"String"`.

**Export file (v1, stays v1)**, one key per line:

```
before
{"diceKey":"FDWC…","kind":"age","name":"backups","publicKey":"age1…"}
(default keys left out)

after
{"diceKey":"FDWC…","kind":"age","name":"backups","publicKeys":{"mlkem768x25519":"age1pq1…","x25519":"age1…"}}
{"diceKey":"FDWC…","kind":"age","publicKeys":{"mlkem768x25519":"age1pq1…","x25519":"age1…"}}
{"diceKey":"FDWC…","kind":"ssh","publicKeys":{"ed25519":"ssh-ed25519 AAAA…"}}
```

- `CatalogFile.KeyItem.publicKey: String?` becomes `publicKeys: [String: String]?`
  (written for the file; nil for paper). A key with no public half writes no `publicKeys`.
- Reading: every field other than `diceKey` and `publicKeys` is a recipe field. The map is
  never imported: public keys only come from deriving here.
- Default keys are written like any other key, their recipe being their literal.
- Importing a default the catalog already has is a no-op, as for any existing key.

**Paper (link and recovery code, v2, stays v2)** carries the defaults too:

```
before  {"centerFace":"M1t","id":"FDWC…","keys":[{"kind":"ssh","name":"github"}],"name":"Home box","v":2}
after   {"centerFace":"M1t","id":"FDWC…","keys":[{"kind":"age"},{"kind":"ssh"},{"kind":"ssh","name":"github"}],"name":"Home box","v":2}
```

Older builds already read a nameless default literal (`KeyRecipe` matches it to
`defaults`), so this is compatible both ways.

What changes on paper is only what the codes and the file carry. What is printed for
people stays as today:

- The list card's and recovery sheet's printed key lists show named keys only, as now, so
  they keep their room (`listedKeys`) and no default prints as "SSH · SSH". Keep the
  printed lists on named keys even though `CatalogFile(records:entries:)` now includes
  defaults.
- The recovery sheet's one public-key line per key prints the kind's first algorithm's
  public key (today's behavior; the post-quantum one can't fit a line).
- The capacity floors (`PaperTests`: 40 keys on the card, 80 on the sheet) stay as counts of
  named keys, now measured with the two defaults in the payload as well. The capacity
  figures in `catalog-format.md` are re-measured.
- Counts shown to people before an import or restore (`CatalogImport.swift`,
  `RecoveryRestore.swift`) exclude defaults, so the count is the keys the person made.

**`kinds.json` and `scripts/derive-kinds.py`** take the same shape: each case and default
replaces `type`, `publicKey`, `fingerprint`, `secret` and `postQuantum` with

```
"algorithms": [
  {"type": "x25519", "publicKey": "age1…", "fingerprint": "age1…", "secret": "AGE-SECRET-KEY-1…"},
  {"type": "mlkem768x25519", "publicKey": "age1pq1…", "secret": "AGE-SECRET-KEY-PQ-1…"}
]
```

Every value is byte-identical to today's file. The builder proves it with a one-off
comparison of old and new values before replacing the file, and says so in the PR.
`check_tools` (age-keygen, ssh-keygen, wg in CI) iterates the list.

### Screens

- **Key screen**: one public-key section per algorithm with a public half, in kind order.
  A kind with one algorithm keeps today's single "Public key" section (with no
  fingerprint, as today: the key screen never shows one; only New key does); a kind with
  several titles each section by algorithm and shows its note. A section whose
  key the catalog doesn't hold yet says "Shows once the DiceKey is unlocked."; Unlock shows
  once, under the first such section. Reveal shows every algorithm's secret, each labeled
  when there are several, each with Copy and Share; SSH and age share as the file their
  tool reads.
- **New key**: the preview shows every algorithm's public key, as now for age.
- **Per-algorithm display data** (app side, beside `KeyKind+Display.swift`), keyed by kind
  and type, replacing `AgeRecipient`: title, note, folded lines, file name. Today's values:

| Kind | Type | Title | Note | Folded | File |
|---|---|---|---|---|---|
| ssh | ed25519 | (Public key) | none | | `id_ed25519[_name]` |
| wireguard | x25519 | (Public key) | none | | |
| age | x25519 | X25519 | today's `x25519Note` | | `age[-name].txt` |
| age | mlkem768x25519 | ML-KEM-768 + X25519 (post-quantum) | today's `postQuantumNote` | 4 | `age-pq[-name].txt` |

The app's look and wording don't change for any existing kind.

### Rules written into the docs

- `derivation.md`: the Kinds table lists each kind's algorithms. A kind's algorithm set
  only grows; a released algorithm is never removed or retyped; types are distinct within
  a kind. If a default ever stops being added to new DiceKeys, its literal stays accepted
  by the parser, so files and paper that carry it can still make the key.
- `catalog-format.md`: `publicKeys` in the file; defaults in every form; re-measured
  capacity. Its examples show the new forms only.
- `security.md`: the catalog holds every algorithm's public key; filling one in derives the
  whole key and drops the rest at once.
- `design.md`: the key screen's sections, per above.

## Spike (done, throwaway, macOS SwiftData, a real store file)

- A store made with today's `KeyEntry`, opened by a build adding
  `publicKeys: [String: String] = [:]`, migrates automatically; rows read `[:]`.
- Writing `x25519` plus an unknown name, then reopening in a new process, keeps both.
  Changing one entry by subscript and saving keeps the unknown one.
- On disk it is a `BLOB` column holding JSON text.
- `#Predicate` on the map: `.isEmpty` and `.keys` are fatal errors at fetch;
  a subscript is an `unsupportedPredicate` error.
- An older build opening the newer store migrates the column away; the newer build sees
  `[:]` and the fill restores it on unlock.
- Not tested: CloudKit's mirror of the column. Checking sync on two devices is already in
  `docs/backlog.md`; this adds the field to the schema deploy there.

## Tests the change needs (TDD)

- Each kind's `DerivedKey.algorithms` matches `kinds.json`, all types and values.
- `needsPublicKey`: true for a missing algorithm, false for passphrase and wallet and for a
  complete entry.
- The fill keeps a map entry whose name this version doesn't know.
- Export writes `publicKeys` for every key with a public half, includes the defaults, and
  round-trips.
- Paper includes the defaults and round-trips.
- `CompatibilityTests` updated as above.
- The old fixtures (`catalog-v1.json`, `catalog-link-v2.txt`, `recovery-v2.txt`) are
  deleted and replaced by fixtures in the new forms, generated once by the new code, checked
  by hand against this document, and from then on never edited. `CatalogFormatV1Tests` and
  `PaperFormatV2Tests` pin them as they pin today's: decode to exactly the expected DiceKeys
  and keys, and today's encoder writes them back.
- The existing suite passes (123 app tests at the time of writing), with
  `swift format lint --strict`, `swiftlint lint --strict` and the Python checks clean.

## Left to the builder

- Exact Swift names beyond those above, file layout, and how the display data is keyed.
- Whether `Age.postQuantum(seed:)` is reshaped or wrapped.
- How the one-off `kinds.json` value comparison is done (it isn't committed).
- Commit boundaries.

## Calls made during design (owner can overrule)

- Algorithm names are `DerivableType` raw values, not display names.
- A kind with one algorithm keeps today's single "Public key" section.
- The file stays v1 and paper stays v2; older builds warn through "couldn't be read."
- Nothing stays compatible with pre-release data, the store included: no test opens a
  store in the TestFlight builds' shape.
- `kinds.json` is reshaped to the generic list rather than left with `postQuantum`.
- The fill trigger queries all entries rather than filtering in the store.
- Paper's codes carry the defaults; its printed lists, counts and public-key line stay on
  named keys and the first algorithm, as today.
- The dictionary column ships if the device sync check passes, with `publicKeysJSON` as the
  named fallback.
- No fingerprint is added to the key screen.
