# Derivation

`Packages/Derivation` turns a DiceKey seed and a recipe (`recipe-format.md`) into a password,
a secret or a key. The construction, the first two word lists and the JSON layouts are ported
from dicekeys/seeded-crypto, which the other DiceKeys apps shared. That reference behavior is
the backward-compatible subset of what this package does: a recipe that derived before derives
the same bytes and the same string, unless it already carried `separator` or
`capitalize` as salt, and `vectors.json` proves it. Beyond that subset the format is this
app's to grow, one field or list name at a time, and a name the package does not know is an
error rather than a fallback.

## The construction

`info` is the type string (`Password`, `Secret`, `SymmetricKey`, `UnsealingKey` or
`SigningKey`) followed immediately by the recipe text as UTF-8. The empty recipe hashes as
the type string alone. The seed is the UTF-8 seed string. With keyed BLAKE2b at 32-byte
digests (`HKDF.swift`):

```
PRK  = BLAKE2b(key = 32 zero bytes, message = seed)
T(0) = empty
T(i) = BLAKE2b(key = PRK, message = T(i-1) || info || UInt8(i))     i = 1 ... ceil(L / 32)
out  = the first L bytes of T(1) || T(2) || ...
```

`L` is the length the recipe resolves to. It is at most 8160, so the one-byte counter never
wraps.

## Per type

- **Password.** The derived bytes are read as 8-byte big-endian blocks; a block modulo the
  list size picks an entry, and the quotient supplies digit separators and the capitalized
  word of the modern joining (`recipe-format.md`, Joining). The modulo is unbiased for a
  power-of-two list and biased by at most size / 2^64, about 2^-51 for the EFF list, for
  the others. The output is cut to `lengthInChars` characters if the recipe sets it.
- **Secret.** The derived bytes, `lengthInBytes` of them.
- **SymmetricKey.** The 32 derived bytes.
- **UnsealingKey.** `unsealingKeyBytes` is the first 32 bytes of SHA-512 of the 32 derived
  bytes, unclamped; `sealingKeyBytes` is the X25519 public key for that scalar.
- **SigningKey.** The 32 derived bytes are the Ed25519 seed. `verificationKeyBytes` is the
  public key, and `signingKeyBytes` is the seed followed by the public key, 64 bytes, the
  layout libsodium uses for a secret key.

## Word lists

`recipe-format.md` lists the nine lists and their kinds. The reference's two are in
`WordLists.swift`; this app's are generated or literal. `WordList.words(forBits:)` is the
fewest entries whose combinations reach 2^bits, computed in floating point and checked for
every list and bit count against an exact multi-limb comparison in `WordListTests`.

The app's sheet reports strength in zxcvbn's bands (guesses under 10^3, 10^6, 10^8, 10^10),
computed from bits as 2^bits since every value is uniform.

## JSON output

`toJson()` returns the engine's text unchanged, because it is a displayed format that other
DiceKeys apps also show. Keys are in byte order, there is no whitespace, `/` is not escaped,
non-ASCII is written raw, control characters are `\b \f \n \r \t` or lowercase `\u00xx`, and
byte arrays are lowercase hex without a prefix.

| Type | Keys | `recipe` when the recipe is empty |
|---|---|---|
| Password | `password`, `recipe` | omitted |
| Secret | `recipe`, `secretBytes` | omitted |
| SymmetricKey | `keyBytes`, `recipe` | omitted |
| UnsealingKey | `recipe`, `sealingKeyBytes`, `unsealingKeyBytes` | present, as `""` |
| SigningKey | `recipe`, `signingKeyBytes` | present, as `""` |

## Key formats

`KeyFormats` encodes a `SigningKey` (OpenSSH, OpenPGP) and Secret bytes (BIP39).

**OpenSSH.** The public line is `ssh-ed25519 <base64> DiceKeys`. The private key is an
unencrypted `openssh-key-v1` block (cipher and KDF `none`, one key) in 64-column base64 with
the `OPENSSH PRIVATE KEY` armor. Its private section holds the check value twice, the key
type, the public key, the 64-byte signing key, the comment (empty by default) and padding
bytes 1, 2, 3 and so on up to a multiple of 8. OpenSSH's check value exists to detect a wrong
passphrase; here it is the first four bytes of SHA-256 of the public key, so the export is
identical every time.

**OpenPGP.** An armored transferable secret key: a v4 secret key packet (EdDSA, algorithm 22,
Ed25519 OID, unprotected, with the 16-bit checksum), a user ID packet, and a positive
certification self-signature (type 0x13, SHA-256) whose key flags are certify plus sign. The
armor has the blank line after the header and a CRC24 line. Packets use the old framing, with
1, 2 or 4 length octets as the body needs. The creation time is 0 because the v4 fingerprint
hashes it, so the fingerprint depends on the key alone. CryptoKit randomizes Ed25519
signatures, so two exports of one key differ only inside the signature packet (the two MPIs,
their bit-length fields and, when a leading zero byte drops, the packet's length octets); the
public key, fingerprint, secret key material and user ID are identical.

**BIP39.** `BIP39.mnemonic(entropy:)` takes 16 to 32 bytes in steps of 4. The English list is
`Wordlist.swift`.

## The seed string

The seed is the DiceKey's human-readable form: 25 faces of letter, digit and orientation,
75 characters (50 without orientations, which only tests use), rotated to whichever of the
four rotations sorts first, so every way of holding the key derives the same values.
`DiceKey.toSeed()` builds it.

`DiceKey.idBytes` is the 16-byte Secret derived from that seed with the recipe
`{"purpose":"a unique identifier for this DiceKey","lengthInBytes":16}`, and `DiceKey.id` is
its URL-safe base64 without padding. For the example key the bytes are
`31f6979a628e4800780118a5dc466129` in hex.

## Compatibility contract

Each item is covered by a case in `vectors.json`. They describe the reference subset; this
app's extensions are pinned by `extensions.json` instead (see The fixture).

1. The empty recipe hashes as the type string alone; `{}` differs.
2. The recipe text is hashed as given: leading or trailing whitespace, a byte order mark,
   key order and unknown fields all change the output.
3. The extract step is keyed BLAKE2b with a 32-byte zero key, not unkeyed BLAKE2b.
4. The expand step chains `T(i-1)`, starts the counter at 1, rounds up to whole 32-byte
   blocks and truncates.
5. Keys require `lengthInBytes` 32 and accept only their own `algorithm` name.
6. Password words come from 8-byte blocks; the index is the block modulo the list size; the
   prefix is the decimal word count; words are joined by `-`; the first letter of the first
   word is uppercased.
7. `lengthInChars` truncates the finished string, prefix included.
8. The word lists are the reference arrays, in order.
9. The `toJson()` layouts and the presence of `recipe` are as in the table above.
10. Hex is lowercase without a prefix.
11. `signingKeyBytes` is the seed followed by the public key: 64 bytes, 128 hex characters.
12. The X25519 scalar is the first 32 bytes of SHA-512 of the derived bytes, unclamped in
    the JSON.
13. The OpenSSH layout, 64-column base64 and the ` DiceKeys` comment on the public line.
14. The OpenPGP public key body, fingerprint, secret key material and user ID.
15. The seed string is the DiceKey rotated to its lexically smallest form, 75 characters.

## Behaviors the reference had and this does not

The reference implementation accepted recipes that the format never defined, and this one
rejects them. The `legacy` section of `vectors.json` records what the reference produced for
each recipe that shows one of the rows below, so the behavior could be restored and verified
against the original. The `rejected` section holds the recipes the reference itself refused,
with its error text.

| The reference | Here |
|---|---|
| `hashFunction: Argon2id` derived through libsodium's internal `argon2id_hash_raw` (salt is the type string plus the recipe, one lane, output of at least 16 bytes cut to the length) | `unsupportedHashFunction` |
| `16.9` read as 16, `true` as 1, a negative `lengthInChars` wrapping to no truncation, values of 2^32 or more cut to 32 bits | `wrongType` or `outOfRange` |
| `lengthInBytes` unbounded, with the HKDF counter wrapping past 8160 bytes | 1 to 8160 |
| `lengthInBytes: 0` an empty secret, `lengthInChars: 0` an empty password, and 0 for bits or words meaning unset | `outOfRange` |
| An unknown `wordList` fell back to the 512 list | `unknownWordList` |
| `algorithm` tolerated on a Password or Secret, and a key's name there forced length 32 | `invalidAlgorithm` |
| The bits and words check multiplied where it should divide, so it accepted some wrong pairs and refused correct ones | the check in `recipe-format.md` |
| A duplicate name: the last value won | `duplicateField` |
| A recipe that was not an object raised a JSON library error | `recipeNotAnObject` |
| `excludeOrientationOfFaces` documented but never honored | salt only |
| The memory fields with BLAKE2b silently ignored | still ignored, so salt |
| OpenSSH check value random | derived from the public key |
| OpenPGP armor without the blank line or CRC, one-byte packet lengths whatever the size, certify-only key flags | fixed |
| OpenPGP self-signature deterministic | randomized by CryptoKit |
| Sealing, unsealing, signing and verifying as operations, `SealingKey`, `PackagedSealedMessage` | not offered |

## The fixture

`Packages/Derivation/Tests/DerivationTests/Fixtures/vectors.json` holds 168 derivations
(`cases`) recorded from the reference C++ with four DiceKeys, with and without orientations,
across every type, the app's templates, every length field at its bounds, both word lists,
whitespace, key order and byte order mark variants, unknown fields and nested objects.
Signing-key cases carry the OpenSSH and OpenPGP exports as the C++ wrote them. The tests
compare the OpenSSH private key with the check value masked, and the OpenPGP export by parsed
content, because the port changed the armor, the length encodings, the key flags and the
signature bytes.

The generator and the C++ it ran are gone, so the fixture cannot be regenerated. It is the
reference: if `VectorTests` fails, the derivation changed, and the fixture is not what to fix.

`Fixtures/extensions.json` holds this app's extensions: the new lists, the modern joining
and the character-set length rule, derived with the first fixture key. It was generated by
this engine (`ExtensionVectorTests.regenerate`, with `REGENERATE_EXTENSIONS_FIXTURE=1`), so
it can be regenerated, but only to add cases; a changed value is a changed password.

The BLAKE2b implementation is also tested against RFC 7693 and the official known-answer
vectors (`Tests/BLAKE2Tests`).

## Secrets in memory

Derived values are ordinary Swift values, and nothing zeroes or locks their memory. The
package never logs them. The app holds a derived value in the state of the screen showing
it, so it goes when the screen does; the DiceKey id, which the `DiceKey` caches, is the
exception. The app copies a value to the general pasteboard marked local
only, so Universal Clipboard does not carry it, with an expiry one minute out.

## Adding a hash function or a word list

Add one case to `HashFunction` or `WordList` with its implementation, a digest in
`WordListTests`, and cases in `ExtensionVectorTests` and regenerate the fixture. The name
then becomes part of the format and cannot change. A list is generated by
`scripts/generate-wordlists.py` when it has a source, or written as a literal when it is
short enough to read.
