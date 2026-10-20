# Derivation

A DiceKey, a kind and a name always derive the same key, on any device, forever. Nothing
derived is ever stored. This is exact enough to reimplement from; `scripts/derive-kinds.py`
is such a reimplementation.

## The seed

The DiceKey's 25 faces in reading order, each as letter, digit and orientation (`A1t`: `t`,
`r`, `b`, `l` for the top of the letter pointing up, right, down, left), 75 ASCII characters.
Of the four quarter turns of the box, the one whose string sorts first is the seed, so every
way of holding the box derives the same keys (`DiceKey.seed`).

## The construction

The DiceKeys reference construction, kept so that any DiceKeys app or the reference C++ can
still derive the same bytes. HKDF with keyed BLAKE2b at 32-byte digests (`HKDF.swift`):

```
info = type || recipe          (UTF-8, no separator; type is SigningKey, UnsealingKey, Password or Secret)
PRK  = BLAKE2b(key = 32 zero bytes, message = seed)
T(i) = BLAKE2b(key = PRK, message = T(i-1) || info || UInt8(i))     i = 1, 2, …   T(0) = empty
out  = first L bytes of T(1) || T(2) || …
```

The recipe text is hashed exactly as written, so the app only writes it one way: the recipe's
fields as RFC 8785 (JCS) canonical JSON, keys sorted by UTF-16 code unit, no whitespace,
strings escaped minimally. The DiceKey id recipe alone is the reference's text, unchanged, so
ids match the DiceKeys apps.

## Kinds

`KeyRecipe` builds the recipe; `DerivedKey` derives and encodes it.

| Kind | Type | Recipe | Gives |
|---|---|---|---|
| SSH | SigningKey | `{"purpose":"ssh:<name>"}` | Ed25519: the 32 derived bytes are the seed. OpenSSH `openssh-key-v1`, unencrypted, check value = first 4 bytes of SHA-256 of the public key, comment = name; `ssh-ed25519 <base64> <name>`. |
| WireGuard | UnsealingKey | `{"purpose":"wireguard:<name>"}` | Scalar = first 32 bytes of SHA-512 of the derived bytes, unclamped; private and public keys in base64. |
| age | UnsealingKey | `{"purpose":"age:<name>"}` | The same scalar. `AGE-SECRET-KEY-1…` (Bech32, HRP `age-secret-key-`, checksum over lower case, then upper-cased) and `age1…`. |
| Passphrase | Password | see below | Characters or words. |
| Wallet | Secret | `{"purpose":"wallet:<name>"}` | 24-word BIP39 English phrase from 32 bytes, Secret's default length; no BIP39 passphrase. |
| DiceKey id | Secret | `{"purpose":"a unique identifier for this DiceKey","lengthInBytes":16}` | 16 bytes as unpadded URL-safe base64. One-way; it reveals nothing about the dice. |

The kind prefix in `purpose` keeps kinds apart even where they share a type. WireGuard, age
and CryptoKit each clamp the scalar before use, so all three agree on the public key.

**Names** are trimmed of Unicode `White_Space` at both ends, normalized to NFC, 1 to 64
scalars, with no `Cc` character, no `Cf` character but the zero-width joiner emoji sequences
need, and no unassigned (`Cn`) code point, so in the JCS text only `"` and `\` are ever
escaped. Invisible characters would let a name that prints the same derive a different key,
and an unassigned code point could normalize differently once Unicode assigns it. Otherwise
a name is exactly as typed: one changed character is a different key.

**Passphrases** carry their style in the recipe, so the style is part of the key:

- Random: `{"lengthInChars":<12…64>,"purpose":"passphrase:<name>","wordList":"CHARS_57_letters_digits_20261002"}`,
  or `CHARS_67_letters_digits_symbols_20261002` with symbols. Letters without `I`, `O`, `l`,
  digits without `0`, `1`, symbols `!@#$%&*-_?`. Default 24 characters, about 140 bits.
- Memorable: `{"lengthInWords":<4…10>,"purpose":"passphrase:<name>","separator":"-","wordList":"EFF_large_7776_words_9_chars_max_20160719"}`,
  or with `"capitalize":true` first and `"separator":"digits"`. Default 6 words,
  about 77 bits.

Each character or word is an 8-byte big-endian block of the output modulo the list size, so
the choice is uniform to within size / 2^64. With digits, the digit after word `i` is block
`i`'s quotient modulo 10; with a capital, the word upper-cased is at the last block's quotient
modulo the word count.

## Proof

- `vectors.json`: 168 derivations recorded from the reference C++, which can't be
  regenerated. If `VectorTests` fails, the derivation changed.
- `kinds.json`: every kind, written by `scripts/derive-kinds.py`, which shares nothing with
  the Swift code but the word lists. `KindVectorTests` checks the app against it, and CI runs
  the script with `--tools` to confirm the public keys with `ssh-keygen`, `wg` and
  `age-keygen`.
- `extensions.json`: the passphrase lists and joinings, from this engine; add cases only.
- BLAKE2b against RFC 7693 and the official known answers.

Any change to a derived byte is a bug: it makes someone's key unrecoverable.

The package can still parse the reference's free-form recipes, because the reference vectors
use them; the app never writes one.
