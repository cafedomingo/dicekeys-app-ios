# Derivation

A key is a pure function of a DiceKey, a kind and a name (the default keys have none), and,
for a passphrase, its style. The same inputs give the same key on any device, forever.
No derived secret is ever stored: the catalog keeps only the DiceKey's one-way id and public
keys, and everything else is derived again when it is needed. This document is the
specification. It is exact enough to reimplement on another platform, and
`scripts/derive-kinds.py` is such a reimplementation;
`Packages/Derivation/Tests/DerivationTests/Fixtures/kinds.json` is its conformance suite.

## The seed

A DiceKey is 25 dice in a 5×5 box. Each face is three ASCII characters: a letter (`A`–`Z`
without `Q`), a digit (`1`–`6`) and which way the top of the letter points (`t`, `r`, `b`,
`l` for up, right, down, left), such as `A1t`. The 25 faces in reading order (row by row,
left to right; position = 5 × row + column) are a 75-character text.

The box can be held four ways, and all four must give the same keys. A clockwise quarter turn
moves the die at row r, column c to row c, column 4 − r (so new[r][c] = old[4 − c][r]) and
turns each die's top `t` → `r` → `b` → `l` → `t`. The seed is the smallest of the four texts,
compared byte by byte (`DiceKey.seed`). This is the original DiceKeys rule; kinds.json's
`seeds` pins it with DiceKeys whose seeds were recorded from the original C++.

## The construction

HKDF (RFC 5869) with SHA-256 and no salt, from CryptoKit (`Engine.bytes`):

```
info = type || recipe                    UTF-8, no separator
PRK  = HMAC-SHA256(key = 32 zero bytes, message = seed)
T(i) = HMAC-SHA256(key = PRK, message = T(i-1) || info || i)     i = 1, 2, …; T(0) is empty
out  = the first L bytes of T(1) || T(2) || …
```

No salt is RFC 5869's 32 zero bytes. The counter is one byte; the longest output, a
64-character passphrase, is 512 bytes, far below its 255 blocks. Any standard HKDF-SHA256
gives these bytes (Android's, WebCrypto's, Python's `hmac`); kinds.json's `hkdf` pins the
construction alone.

## Recipes

A recipe says what to derive. It is JSON, and its text is what gets hashed:

```
{"kind":"ssh","name":"github"}
{"kind":"passphrase","length":24,"list":"letters-digits","name":"nas"}
{"kind":"passphrase","length":6,"list":"eff_large_wordlist","name":"nas","separator":"digits","uppercase":true}
```

The fields are `kind` (`ssh`, `wireguard`, `age`, `passphrase` or `wallet`) and `name`, and
for a passphrase `length` and `list`, with `separator` and `uppercase` for words (see
Passphrases). Nothing else. Only the default keys have no `name` (see Default keys). The
types are not in the JSON: the kind decides them.

**One spelling.** A recipe is written as RFC 8785 (JCS) canonical JSON: keys sorted by UTF-16
code unit, no whitespace, integers in plain decimal, non-ASCII written as raw UTF-8 (never
`\uXXXX`), and strings escaped minimally, which for a valid name means only `"` and `\`. Text
is a recipe only if it is, byte for byte, the canonical text of a valid recipe
(`KeyRecipe(json:)`): decode it, write it back, and compare the bytes. That refuses reordered
keys, whitespace, escapes that needn't be, duplicate, missing or unknown fields, `24.0` for
`24`, and a name that isn't already trimmed and normalized.

**Names** are trimmed at both ends of Unicode `White_Space` (U+0009–000D, 0020, 0085, 00A0,
1680, 2000–200A, 2028, 2029, 202F, 205F, 3000), normalized to NFC, and 1 to 64 scalars long.
They may not hold a control character (`Cc`), a format character (`Cf`) other than the
zero-width joiner that most emoji sequences need, or a code point Unicode hasn't assigned
(`Cn`). So an emoji built from tag characters, such as a subdivision flag, is refused.
Invisible characters would let a name that prints the same derive a different key. An
unassigned code point could normalize differently once Unicode assigns it; NFC is stable for
assigned characters. Otherwise a name is exactly as typed: `'` is not `’`, and a different
capital or inner space is a different key.

The unassigned check follows each platform's Unicode tables, so a name using a code point
newer than a device's tables (in practice, a new emoji) is refused there. That only ever
refuses a name; it never derives a different key.

## Kinds

`KeyRecipe` builds the recipe; `DerivedKey` derives and encodes the key. A kind derives an
ordered list of algorithms from its one recipe, one key each (`KeyKind.algorithms`). An
algorithm is a type. The type is hashed in front of the recipe and names what the bytes become.

| Kind | Algorithms |
|---|---|
| ssh | `ed25519` |
| wireguard | `x25519` |
| age | `x25519`, `mlkem768x25519` |
| passphrase | `passphrase` |
| wallet | `bip39` |

| Type | L | Key |
|---|---|---|
| `ed25519` | 32 | The bytes are the Ed25519 seed. |
| `x25519` | 32 | The bytes are the X25519 scalar, unclamped. |
| `mlkem768x25519` | 32 | The bytes are the X-Wing seed that an age 1.3 identity holds. SHAKE256 of it gives 96 bytes: ML-KEM-768's seed (d ‖ z), then the X25519 secret. |
| `passphrase` | 8 per entry | See Passphrases. |
| `bip39` | 32 | The bytes are the BIP39 entropy. |

WireGuard and age share the type `x25519` and differ by `kind` in the recipe. An age key
derives both of its identities from its one recipe; their types keep them independent. The
X25519 scalar is clamped by the curve library when it is used (CryptoKit, libsodium and
Python's `cryptography` all clamp internally), so every tool agrees on the public key; a port
must use a library that does the same.

The rules for algorithms:

- A kind's algorithm set only grows. A released algorithm is never removed or retyped.
- The types within a kind are distinct, because the same type would derive the same bytes.
- The order is emphasis only, and it may change, since nothing stored depends on it.

**Encodings.** These turn key bytes into the text each tool reads. They are standard formats,
pinned by kinds.json, but they are not key material: the key would survive a change to them,
the exported text would not.

- **ssh**: the public key line is `ssh-ed25519 <base64 of the public key blob> <name>` (for a
  default, no name and no trailing space; see Default keys); the fingerprint is `SHA256:` and
  the unpadded base64 of SHA-256 of that blob. The private key is an unencrypted OpenSSH
  `openssh-key-v1` file (PROTOCOL.key): cipher and KDF `none`, empty KDF options, one key; the
  private section is the check value twice (the first 4 bytes of SHA-256 of the raw 32-byte
  public key), the key type, the public key, seed ‖ public key, and the name as the comment,
  padded with bytes 1, 2, 3, … to a multiple of 8; the PEM is wrapped at 64 columns and ends
  with a newline.
- **wireguard**: the private scalar and the public key in standard base64.
- **age**: `AGE-SECRET-KEY-1…` is Bech32 (BIP 173) with HRP `age-secret-key-`, computed over
  the lower-case string and then upper-cased; the recipient is `age1…`, HRP `age`. The
  post-quantum identity is `AGE-SECRET-KEY-PQ-1…`, HRP `age-secret-key-pq-`, over the 32-byte
  seed, upper-cased the same way; its recipient is `age1pq1…`, HRP `age1pq`, over the 1,184-byte
  ML-KEM-768 encapsulation key followed by the 32-byte X25519 public key, 1,959 characters.
  Bech32 here has no length limit.
- **wallet**: the 24-word BIP39 English phrase, with no BIP39 passphrase.

## Passphrases

A passphrase's style is part of its recipe, so part of the key.

| Style | Fields | List |
|---|---|---|
| Random | `length` 12–64 characters, default 24 | `letters-digits` (57): `ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789`; `letters-digits-symbols` (67): the same followed by `!@#$%&*-_?` |
| Memorable | `length` 4–10 words, default 6; `separator`; `uppercase` | `eff_large_wordlist` (7,776): EFF's large wordlist, its words in file order without the dice numbers |

- `length` is how many entries: characters or words.
- `list` names the list the entries come from, and so the style.
- `separator`, memorable only and always written: `-` joins the words with hyphens, `digits`
  with digits.
- `uppercase`, memorable only: `true` writes one whole word in capitals. It goes with
  `"separator":"digits"` and only with it, so a memorable recipe has two forms, `-` without
  `uppercase` and `digits` with `"uppercase":true`. Anything else, `false` included, is not a
  recipe.

The type is `passphrase`, and L is 8 bytes per character or word. Each entry is one 8-byte
big-endian block of the output modulo the list size; the quotient that is left over is
independent of that choice. Random characters are concatenated. Memorable words are written
in lower case, as the list has them. With `-` they are joined by hyphens. With `digits`, for
n words indexed from 0:

- the word at index (block n − 1's quotient modulo n) has every letter upper-cased, not just
  its first; the list is ASCII letters and hyphens, so this is `a`–`z` to `A`–`Z` alone;
- between word i and word i + 1 goes one digit, block i's quotient modulo 10, so there is no
  trailing digit.

So three words whose blocks pick `abacus`, `abdomen` and `abdominal` with quotients 17, 3
and 4 give `abacus7ABDOMEN3abdominal` (4 modulo 3 is 1). A list's content and order are part
of the format; the SHA-256 of a list's entries joined by `\n` pins it (`PassphraseListTests`).

Strength is exact because every entry is uniform: 24 random characters are about 140 bits, 6
words about 77; the digits and the uppercase word add a little more.

## Default keys

Every DiceKey has an SSH and an age key that need no name. Each recipe holds `kind` alone and
is written as a literal, which is the text that gets hashed, so no change to the code that
writes recipes can change a default key:

| Kind | Recipe text |
|---|---|
| ssh | `{"kind":"ssh"}` |
| age | `{"kind":"age"}` |

A default derives like any key, from `type || recipe`. The parser (`KeyRecipe(json:)`)
accepts a recipe without a name only if its text is, byte for byte, one of these two:
`{"kind":"passphrase"}`, `{"kind":"ssh","length":24}` and `{ "kind":"ssh" }` are refused. No
literal equals a named recipe's text, since those hold `"name"`, and each starts with `{`, so
`type || recipe` still reads only one way.

Once an App Store release has a literal, it is never edited or removed, because a default has
no name to make its key again and synced catalogs hold its rows. The set changes only by
adding one, and an added literal reaches every DiceKey: the app adds each default a DiceKey
lacks. If a default ever stops being added to new DiceKeys, its literal stays accepted by the
parser, so files and paper that carry it can still make the key. A catalog row whose recipe
has no name and isn't one of these, such as `{"kind":"wireguard"}` from a test build, is left
out like any recipe this version can't read, and the DiceKey's other keys load as usual.

Without a name, the encodings that use one fall back. The SSH public key line is
`ssh-ed25519 <base64>`, with no comment and no trailing space, and the private key's comment is
empty. Exported files take the tool's name alone: `id_ed25519`, `age.txt` and `age-pq.txt`.

## The DiceKey id

16 bytes with type `dicekey-id` and an empty recipe, so `info` is just `dicekey-id`, written
as unpadded URL-safe base64 (`DiceKeyID`). It names a DiceKey in the catalog and on paper
without revealing anything about the dice.

## Why keys are stable

A key depends on three byte strings and nothing else: the seed, the type, and the recipe
text. No randomness, clock, device, app version or stored salt goes in. So these must never
change:

- the seed's text and the rotation rule;
- the construction (HKDF-SHA256 with no salt, as above);
- the type strings, and the types each kind derives, a set that may only grow;
- each kind's fields: their names, their values, the list names, and when an optional field
  is written (`uppercase` only with digits, and only as `true`);
- the default recipe texts, which are literals;
- the lists' contents and order;
- the name rules, except to loosen them: a name accepted today must stay acceptable;
- the JCS rules, which are a published standard.

Every (kind, name, style) has exactly one recipe text, because names are normalized and the
JSON is canonical, and the parser accepts nothing else. A default has exactly one too: its
literal. The format grows by adding: a new kind, a new type, a new algorithm for a kind, a
new list or a new default leaves every existing string alone. A new field must never be added
to an existing kind with a default that changes its text. A key is replaced by giving it a new
name (`github 2`), so a default key can't be replaced; there is no other version counter.

If a test below fails, a derived byte has changed: fix the code, never the fixture.

## Why it is safe

- **The seed is the secret, and it is strong.** 25! orderings × 6^25 digits × 4^25 turns is
  about 2^198 arrangements; the four turns of a box are one key, so about 2^196 seeds. Nobody
  can search that, which is why the construction is a fast hash and not a slow
  password-hashing function, which would be needed for a secret a person chooses.
- **The construction is a standard KDF.** HKDF-SHA256 from the platform's own cryptography,
  with nothing hand-written; extracting without a salt is fine because the seed already has
  full entropy.
- **Every key is independent.** `info` differs for every (type, recipe), so the outputs are
  unrelated: a leaked SSH key says nothing about the same name's WireGuard key, another name's
  key, or the DiceKey. No type string is a prefix of another and every recipe starts with `{`,
  so `type || recipe` reads only one way, and the id's `info` can't equal any key's.
- **Nothing runs backward.** No output reveals the seed; the id and the public keys can be
  stored and shared.
- **Choices are uniform.** An 8-byte block modulo a list of n entries is biased by at most
  n / 2^64, under 2^-51 for the largest list.

`security.md` covers what is stored, where, and the limits.

## What the tests pin

- **kinds.json**, written by `scripts/derive-kinds.py`, which shares nothing with the Swift
  code but the word lists:
  - `seeds`: text as typed and its canonical seed (checked against the original DiceKeys C++);
  - `hkdf`: seed, type, recipe text, length and the raw output in hex;
  - `diceKeyIds`: seed and id;
  - `cases`: derivations across every kind and style, each with `seed`, `kind`, `input`
    (the name as typed, to exercise normalization), `name`, `style`, `recipe`, and
    `algorithms`, one per algorithm of the kind in order, each with its `type` and the
    `publicKey`, `fingerprint` and `secret` its tool reads (a passphrase or a wallet has no
    `publicKey` or `fingerprint`, and age's post-quantum key has no `fingerprint`);
  - `defaults`: each default for each seed, with `seed`, `kind`, `recipe` (its literal) and
    `algorithms` as above.

  `KindVectorTests` and `DiceKeySeedTests` check the app against it, including each kind's
  algorithms in order and that every recipe parses back to itself. CI runs the script with
  `--tools`, so `ssh-keygen`, `wg` and `age-keygen` 1.3 read every key back, `age` encrypts to
  every age recipient and the identity decrypts it, and the BIP39 reference decodes every
  phrase.
- `KeyRecipeTests`: the name rules, JCS escaping and ordering, text that isn't a canonical
  recipe, and the default literals byte for byte, with any other text that has no name
  refused.
- `PassphraseListTests` and `PasswordFormatterTests`: the lists' digests and literal character
  sets; blocks, quotients, digits and the uppercase word.
- `OpenSSHFileTests`: `ssh-keygen` reads the private key file.
- `age-pq-spec.txt`: the post-quantum example pair from the age specification.
- HKDF-SHA256 against RFC 5869's test cases 1 and 3 in the script and case 3, the no-salt
  form, in Swift; BIP39 against its reference vectors.
