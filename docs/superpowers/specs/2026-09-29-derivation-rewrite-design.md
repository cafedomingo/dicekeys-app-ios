# Derivation rewrite: design

Replace `Packages/SeededCrypto` (libsodium compiled from source, the seeded-crypto C++
subtree, a C ABI shim, and a Swift wrapper) with a pure Swift package over CryptoKit and one
BLAKE2b implementation of our own. Derived outputs stay byte for byte identical for every
recipe the app can produce or that the DiceKeys TypeScript app would accept, except where a
behavior is listed under "Legacy behaviors" below.

This spec is temporary. It is deleted in the final PR of the sequence; durable knowledge
moves into `docs/derivation.md`, `docs/recipe-format.md` and the code.

## Decisions

- **Seal, unseal, sign and verify are dropped as API operations.** No screen calls them.
  Sealing needs XSalsa20-Poly1305, the one libsodium primitive that CryptoKit lacks and
  that is not worth reimplementing. (Signing survives internally for the OpenPGP
  self-signature, through CryptoKit.)
- **Argon2id is dropped.** No DiceKeys app ever surfaced it. `"hashFunction":"Argon2id"`
  throws `unsupportedHashFunction`. Vectors are captured from the C++ so a future
  implementation can be verified (backlog item).
- **BLAKE2b is implemented in Swift here**, not taken as a dependency. No maintained package
  exists: swift-sodium ships libsodium as a binary xcframework, the pure Swift candidates have
  single-digit stars and untagged APIs, and swift-crypto and CryptoSwift have no BLAKE2.
  About 150 lines from RFC 7693, exhaustively tested (see Testing).
- **CryptoKit supplies everything else:** SHA-512, `Insecure.SHA1`, Curve25519 signing and
  key agreement. Verified: for the same 32-byte seed CryptoKit's Ed25519 public key equals
  libsodium's, and `Curve25519.KeyAgreement.PrivateKey(rawRepresentation:)` accepts an
  unclamped scalar, keeps it as given, and yields the same public key as
  `crypto_box_seed_keypair`.
- **OpenPGP self-signatures are not byte-stable.** CryptoKit's Ed25519 randomizes signatures
  by design. The key, fingerprint and every other byte of the export stay fixed; only the 64
  signature bytes vary between derivations. The TypeScript app already varies more (it stamps
  the current time into the key), and no app stores or compares the export.
- **No compatibility with this port's own past output where it was wrong.** There is no
  installed base to protect. Bugs are fixed and the original behavior is documented so it
  could be restored.
- **Strict recipe parsing.** The C++ coerced `16.9` to 16 and `true` to 1 and accepted any
  size. The Swift parser rejects what the format does not define and bounds every integer.
- **Hash functions are an enum, not a protocol registry.** Adding one is one case and one
  file. Unknown names throw; nothing falls back.
- **The migration seam is the whole derive call.** A `DerivationEngine` protocol with two
  implementations (the current C++ behind the existing shim, and the new Swift) runs the
  same test matrix. The protocol is deleted with the C++.
- **Recipe validation is hand-written**, with the schema published as a JSON Schema document
  for readers and for fixture checks. No schema library.
- **Docs live in `docs/` as Markdown**, not a wiki.

## Package layout

```
Packages/Derivation/
  Package.swift
  Sources/BLAKE2/                 BLAKE2b: keyed and unkeyed, streaming and one-shot.
  Sources/Derivation/             Recipe, HashFunction, derived types, JSON output, errors.
  Sources/KeyFormats/             OpenSSH, OpenPGP, BIP39.
  Tests/BLAKE2Tests/              RFC and KAT vectors, streaming, libsodium cross-check.
  Tests/DerivationTests/          fixture-driven matrix, validation, error cases.
  Tests/KeyFormatsTests/          format vectors, ssh-keygen and PGP structural checks.
```

`BLAKE2` is internal to the package (`Derivation` depends on it; it is not a product).
`KeyFormats` depends on `Derivation` for the key types only. The app depends on both
products. `project.yml` swaps `SeededCrypto` for `Derivation`. `.github/dependabot.yml` gains
a `swift` entry for `/Packages/Derivation` even though it declares no remote dependency
today, so a future one is covered.

## Public API

```swift
public enum DerivableType: String, Sendable {
    case password = "Password", secret = "Secret", symmetricKey = "SymmetricKey",
         unsealingKey = "UnsealingKey", signingKey = "SigningKey"
}

public struct Recipe: Sendable {
    public let json: String                 // raw text, hashed exactly as given
    public let type: DerivableType
    public let hashFunction: HashFunction   // .blake2b
    public let lengthInBytes: Int           // resolved: default, key size, or words * 8
    public let lengthInChars: Int?          // password only
    public let wordList: WordList           // password only
    public let lengthInWords: Int           // password only, resolved
    public init(json: String, type: DerivableType) throws(DerivationError)
}

public enum HashFunction: String, Sendable {
    case blake2b = "BLAKE2b"
    func derive(seed: some Sequence<UInt8>, info: [UInt8], outputLength: Int) -> [UInt8]
}

public enum WordList: String, Sendable {
    case en512 = "EN_512_words_5_chars_max_ed_4_20200917"
    case en1024 = "EN_1024_words_6_chars_max_ed_4_20200917"
    public var words: [String]
}

public struct Password: Sendable     { public let password: String; public let recipe: Recipe }
public struct Secret: Sendable       { public let bytes: Data; public let recipe: Recipe }
public struct SymmetricKey: Sendable { public let keyBytes: Data; public let recipe: Recipe }
public struct UnsealingKey: Sendable { public let unsealingKeyBytes: Data
                                       public let sealingKeyBytes: Data; public let recipe: Recipe }
public struct SigningKey: Sendable   { public let signingKeyBytes: Data      // seed || public
                                       public let verificationKeyBytes: Data; public let recipe: Recipe }

// On each of the five:
public static func derive(seed: String, recipe: String) throws(DerivationError) -> Self
public func toJson() -> String

public enum DerivationError: Error, Equatable {
    case recipeNotAnObject, invalidJson(String), duplicateField(String)
    case wrongType(field: String, expected: String)
    case outOfRange(field: String, allowed: ClosedRange<Int>)
    case typeMismatch(recipe: DerivableType, requested: DerivableType)
    case invalidAlgorithm(String), unsupportedHashFunction(String), unknownWordList(String)
    case lengthMustBe32(DerivableType), bitsAndWordsConflict
}
```

`KeyFormats`:

```swift
public enum OpenSSH {
    public static func publicKeyLine(_ key: SigningKey) -> String
    public static func privateKeyPEM(_ key: SigningKey, comment: String = "") -> String
}
public enum OpenPGP {
    public static func secretKeyBlock(_ key: SigningKey, userId: String = "", timestamp: UInt32 = 0) -> String
}
public enum BIP39 {
    public static func mnemonic(entropy: Data) throws -> String   // moved from DiceKeys/Model/BIP39
}
```

The engine seam, present only until the C++ is deleted:

```swift
protocol DerivationEngine {
    func derive(_ type: DerivableType, seed: String, recipe: String) throws -> DerivedJSON
}
```

`DerivedJSON` is the `toJson()` string plus, for signing keys, the three formatted exports.
`LegacyEngine` wraps the current `SeededCrypto` package; `SwiftEngine` is the new code.

## Recipe format

Source: `Vendor/seeded-crypto/doxygen/JSON Format for Derivation Options.md`, reduced to
what any implementation ever acted on. The full text is harvested into
`docs/recipe-format.md`; `docs/recipe-schema.json` is the same in JSON Schema.

A recipe is the empty string or a JSON object. The text is hashed exactly as given, so
whitespace, key order and unknown fields all change the output. Only these fields are read:

| Field | Type | Applies to | Default | Allowed |
|---|---|---|---|---|
| `type` | string | all | the requested type | must equal the requested type |
| `algorithm` | string | keys | per type | `XSalsa20Poly1305` for SymmetricKey, `X25519` for UnsealingKey, `Ed25519` for SigningKey; an error on Password and Secret |
| `hashFunction` | string | all | `BLAKE2b` | `BLAKE2b` |
| `lengthInBytes` | integer | Secret; keys | 32 | Secret: 1 to 8160; keys: 32 |
| `lengthInChars` | integer | Password | none | 1 or more |
| `lengthInBits` | integer | Password | 128 | 1 or more; the resolved word count must fit below |
| `lengthInWords` | integer | Password | from bits | 1 to 1020 (resolved or given) |
| `wordList` | string | Password | `EN_512…` | the two names above |

Everything else (`purpose`, `#`, `allow`, `excludeOrientationOfFaces`,
`clientMayRetrieveKey`, `requireAuthenticationHandshake`, `androidPackagePrefixesAllowed`,
`requireUsersConsent`, `hashFunctionMemoryLimitInBytes`, `hashFunctionMemoryPasses`) is
salt only. `purpose` and `#` are also read by the app for naming and defaults.

Validation rules:

- Integer fields must be JSON integers. Fractions, exponents, booleans, strings and null are
  `wrongType`.
- A key appearing twice is `duplicateField`.
- `lengthInBits` and `lengthInWords` given together must satisfy
  `lengthInWords == ceil(lengthInBits / bitsPerWord)`; otherwise `bitsAndWordsConflict`.
- The password length resolution, in order: `wordList` (default 512); `bitsPerWord` =
  9 or 10; if neither bits nor words is set, bits = 128; if only words is set, bits =
  words × bitsPerWord; if only bits is set, words = ceil(bits / bitsPerWord); then
  `lengthInBytes` = words × 8, overriding any `lengthInBytes` in the JSON.
- Upper bounds come from the HKDF limit of 255 blocks × 32 bytes = 8160 bytes.

## Derivation

**Primary secret.** `info` = the type string (`Password`, `Secret`, `SymmetricKey`,
`UnsealingKey`, `SigningKey`) followed immediately by the recipe text bytes. The empty
recipe hashes as the type string alone; `{}` is different. Then, over keyed BLAKE2b with
32-byte digests:

```
PRK  = BLAKE2b(key = 32 zero bytes, message = seed UTF-8)
T(0) = empty
T(i) = BLAKE2b(key = PRK, message = T(i-1) || info || UInt8(i))   i = 1 ... ceil(L / 32)
out  = first L bytes of T(1) || T(2) || ...
```

Keyed means the RFC 7693 parameter block with key length 32 and the key padded to a
128-byte first block. `L` never exceeds 8160, so the counter never wraps.

**Password.** Read the derived bytes in 8-byte big-endian blocks; each word index is the
block modulo the list size (equivalently its low 9 or 10 bits). Output is the decimal word
count, then `-word` for each word, with the first word's first letter uppercased. Truncate to
`lengthInChars` characters if set.

**Secret.** The derived bytes.

**SymmetricKey.** The 32 derived bytes.

**UnsealingKey.** `unsealingKeyBytes` = first 32 bytes of SHA-512 of the 32 derived bytes,
unclamped. `sealingKeyBytes` = the X25519 public key of that scalar, via CryptoKit.

**SigningKey.** The 32 derived bytes are the Ed25519 seed. `verificationKeyBytes` is the
CryptoKit public key. `signingKeyBytes` = seed followed by public key, 64 bytes, as
libsodium lays it out.

**`toJson()`** reproduces nlohmann's `dump()`: keys in byte order, no whitespace, `/` not
escaped, non-ASCII raw, control characters as `\b \f \n \r \t` or lowercase `\u00xx`,
byte arrays as lowercase hex. Layouts:

| Type | Keys | `recipe` when empty |
|---|---|---|
| Password | `password`, `recipe` | omitted |
| Secret | `recipe`, `secretBytes` | omitted |
| SymmetricKey | `keyBytes`, `recipe` | omitted |
| UnsealingKey | `recipe`, `sealingKeyBytes`, `unsealingKeyBytes` | present as `""` |
| SigningKey | `recipe`, `signingKeyBytes` | present as `""` |

The inconsistency is kept because the JSON is a displayed output format and is what other
DiceKeys apps show.

## Key formats

**OpenSSH.** Layout as today (`openssh-key-v1`, no cipher, no KDF, one key, public blob,
private blob with `checkint` twice, seed || public key, comment, padding 1..n to 8 bytes),
base64 in 64-column lines, `-----BEGIN OPENSSH PRIVATE KEY-----` armor. `checkint` becomes
the first four bytes of SHA-256 over the public key, so the export is stable. The public
key line ends in ` DiceKeys`.

**OpenPGP.** Packets as today: v4 secret key (EdDSA legacy algorithm 22, Ed25519 OID,
unprotected S2K usage 0 with the 16-bit checksum), user ID, positive certification
self-signature (type 0x13, SHA-256, Ed25519 over the digest) with the same hashed
subpackets in the same order. Fingerprint is SHA-1 over the public key body. Three fixes:

- armor gets the required blank line after the header line and a CRC24 line;
- packet and subpacket lengths use the proper multi-octet encodings (the old code wrote
  one byte and corrupted any user ID over 255 characters);
- key flags become certify plus sign (0x03), so PGP tools will sign with the key.

Timestamp stays 0 so the fingerprint never changes. The self-signature bytes vary per
derivation (see Decisions).

**BIP39.** Moves unchanged from `DiceKeys/Model/BIP39/Mnemonic.swift` with its tests.

## Canonicalizer (app)

`DiceKeys/Model/Recipes/CanonicalizeJsonRecipe.swift` is rewritten over JSON tokens to match
the TypeScript reference (`web/src/dicekeys/canonicalizeRecipeJson.ts`):

- numbers and string values are emitted as their original source text;
- booleans as `true`/`false`, null as `null`;
- all whitespace outside strings dropped;
- duplicate keys kept, in order;
- object keys sorted by UTF-16 code unit order, `purpose` first, `#` last, at every level;
- keys are emitted as their original quoted text (the reference decodes them, which produces
  invalid JSON for a key containing an escape; identical for every key without one);
- input that is not a JSON object is rejected (the builder shows the error) instead of being
  passed through verbatim.

The old implementation used `JSONSerialization`, which turned `true` into `1`, reformatted
numbers, unescaped `\/` and `\u007f`, collapsed duplicates to the first, and sorted by
Swift `String` order. Recipes built by the app's own fields never contained any of those, so
only hand-typed raw JSON is affected.

## App changes

- `CustomRecipeModel` loses the `.hosts` build type and `urlString`; `getRecipeJson(hosts:)`
  goes. Purpose and raw JSON remain. Existing saved recipes are strings and keep deriving.
- `DerivationRecipe.derivedValue` calls the new package; `DerivedValue` uses `KeyFormats`
  for OpenSSH, OpenPGP and BIP39. `SeededCryptoRecipeType` becomes a typealias or is replaced
  by `DerivableType`.
- `DerivedValueScreen` no longer falls back to `DiceKey.Example` when no key is loaded; it
  renders nothing.
- No `description` or `debugDescription` on the derived types; the package's types are
  plain structs and the app never prints them.
- Backlog, not this work: the password screen (raise the `lengthInChars` floor, show bit
  strength, a hash function selector, ideas from the TypeScript and Android builders).

## Compatibility contract

Behaviors the Swift engine must reproduce. Each is a fixture case.

1. Empty recipe hashes as the type string alone; `{}` differs.
2. The recipe text is hashed as given: leading or trailing whitespace, a BOM, key order and
   unknown fields all change the output.
3. Extract uses keyed BLAKE2b with a 32-byte zero key, not unkeyed BLAKE2b.
4. Expand chains `T(i-1)`, starts the counter at 1, rounds up to whole 32-byte blocks and
   truncates.
5. Keys require `lengthInBytes` 32 and accept only their own `algorithm` name.
6. Password words iterate over the derived buffer in 8-byte steps; index = block mod list
   size; prefix is the decimal word count; join with `-`; uppercase the first byte of the
   first word.
7. `lengthInChars` truncates the finished string, prefix included.
8. Word lists are exactly the vendored arrays in order.
9. `toJson()` layouts and `recipe` presence per the table above.
10. Hex is lowercase without prefix.
11. Ed25519 `signingKeyBytes` = seed || public key (64 bytes, 128 hex characters).
12. X25519 scalar = SHA-512(seed)[0..<32], unclamped in the JSON.
13. OpenSSH layout, 64-column base64, ` DiceKeys` public comment.
14. OpenPGP packet contents apart from the three fixes and the signature bytes.
15. Seed string: the human-readable DiceKey rotated to its lexically smallest form, 75
    characters; the DiceKey id recipe is `{"purpose":"a unique identifier for this
    DiceKey","lengthInBytes":16}` and the example key's id is
    `31f6979a628e4800780118a5dc466129`.

## Legacy behaviors

Rejected or changed by the port. Each is recorded in `docs/derivation.md` with what the C++
produced, and captured in the fixture's `legacy` section so it can be restored and verified.

| Was | Now |
|---|---|
| `hashFunction: Argon2id` derived via libsodium's internal `argon2id_hash_raw` (salt = type string + recipe, lanes 1, output max(16, length) truncated) | `unsupportedHashFunction` |
| `16.9` → 16, `true` → 1, `-1` → 4294967295, values ≥ 2^32 truncated to 32 bits | `wrongType` or `outOfRange` |
| `lengthInBytes` unbounded; HKDF counter wrapped past 8160 bytes | 1 to 8160 |
| `lengthInBytes: 0` produced an empty secret; `lengthInChars: 0` an empty password | `outOfRange` |
| Unknown `wordList` fell back to the 512 list | `unknownWordList` |
| `algorithm` on Password or Secret tolerated (any string; a key algorithm name forced length 32) | `invalidAlgorithm` |
| Bits versus words check multiplied instead of divided (rejected correct pairs) | correct check |
| Duplicate keys: last one won | `duplicateField` |
| Non-object recipe raised nlohmann's `type_error.306` | `recipeNotAnObject` |
| `excludeOrientationOfFaces` documented, never honored | salt only, documented |
| Memory fields with BLAKE2b silently ignored | still ignored (salt), documented |
| OpenSSH `checkint` random | derived from the key |
| OpenPGP armor without blank line or CRC; one-byte packet lengths; certify-only flags | fixed |
| OpenPGP self-signature deterministic | randomized by CryptoKit |
| `Recipe.withAllOptionalParametersSpecified`, `sodiumVersion`, `from(json:)`, `SealingKey`, `PackagedSealedMessage`, seal, unseal, sign, verify | removed |

## Testing

**BLAKE2b.**
- RFC 7693 appendix A vector.
- The official `blake2b-kat` known-answer set: unkeyed and keyed, inputs 0 to 255 bytes,
  64-byte digests; plus digest lengths 1 to 64 over the keyed variant.
- libsodium's `generichash` test cases (`test/default/generichash*.c`), which include
  varying key and output lengths.
- Streaming equals one-shot for random split points, including splits on and around the
  128-byte block boundary and an empty final block.
- Edge cases: empty message, empty key, 64-byte key, message lengths 127, 128, 129, 255,
  256, 257.
- While libsodium is still in the tree (before PR 6): 10,000 random inputs and keys
  compared against `crypto_generichash_blake2b_salt_personal`.

**Curves and hashes.** RFC 8032 section 7.1 (Ed25519 key from seed), RFC 7748 section 6.1
(X25519 public key from scalar), through the engine's own code paths. Not a test of
CryptoKit, but of how we call it.

**Fixture.** `Tests/DerivationTests/Fixtures/vectors.json`, generated by
`scripts/generate-vectors.sh` from the C++ before it is deleted. Contents:
- seeds: `DiceKey.Example` plus three more DiceKeys, each with and without orientations;
- every type × every seed × the built-in templates and the empty recipe;
- every length field at its bounds (1, 32, 8160 bytes; 1, 1020 words; bits 1, 128, and
  the largest that resolves to 1020 words; chars 1, 8, 64, and one past the full length),
  both word lists, bits and words together;
- whitespace, key order and BOM variants of one recipe; unknown fields; a nested object;
- `type` present and matching; `algorithm` present and matching;
- error cases with the expected `DerivationError`;
- signing keys with the OpenSSH public line, the OpenSSH private key, and the OpenPGP
  export as the C++ produced them. The Swift tests compare the OpenSSH private key with
  `checkint` masked, and compare the OpenPGP export by parsed content (public key body,
  fingerprint, secret MPI and checksum, user ID, hashed subpacket values other than key
  flags), since the port changes the armor, the length encodings, the key flags and the
  signature bytes;
- a `legacy` section: Argon2id cases and every row of the table above with the C++ output.

**Differential.** `EngineComparisonTests` runs both engines over the whole non-legacy
fixture and asserts equality of `toJson()` and the OpenSSH public line exactly, and of the
OpenSSH private key and OpenPGP export under the same masking and parsed comparison as the
fixture tests. Deleted with the legacy engine in PR 6; the fixture tests remain.

**Canonicalizer.** The TypeScript test cases verbatim, the existing Android-derived cases,
plus numbers (`1.50`, `1e3`, `-0`), escapes (`\/`, `\u007f`, `\u001f`, `\b`), booleans,
null, duplicates, non-ASCII keys, and rejection of non-object input.

**Key formats.** `ssh-keygen -y`, `-l` and `-Y sign` on the OpenSSH output where the tool
is available (macOS test host); OpenPGP parsed by a small test-side packet walker that checks
lengths, the CRC and that the fingerprint matches the fixture; the self-signature verified
with CryptoKit over the reconstructed preimage.

**App.** `CanonicalizeRecipeJsonTests` rewritten; `PasswordDerivationTests`,
`DiceKeySeedTests`, `DefaultOutputFormatTests` and `MnemonicsTests` updated to the new
imports.

## PR sequence

Each PR is squash-merged and stands on its own; CI stays green at every step.

1. **Canonicalizer.** Rewrite and tests. App only.
2. **Vectors.** `scripts/generate-vectors.sh` and `.cpp` replace the golden-vector generator;
   `vectors.json` with the matrix and the `legacy` section; `GoldenVectorTests` reads the
   new fixture. No product code change.
3. **Abstraction.** `Packages/Derivation` with the public API above, `DerivationEngine`,
   `LegacyEngine` over `SeededCrypto`, `KeyFormats` (BIP39 moved; OpenSSH and OpenPGP
   forwarded to the legacy engine); app switched to it; hosts mode removed; example-key
   fallback removed. No output changes.
4. **BLAKE2.** The module and its tests, including the libsodium cross-check.
5. **Swift engine.** `SwiftEngine`, Swift OpenSSH and OpenPGP, `EngineComparisonTests`.
   Default engine stays legacy.
6. **Swap and delete.** Default becomes Swift; `SeededCrypto`, `CSodium`, the subtree, the
   shim, `vendor-libsodium.sh`, `update-seeded-crypto.sh`, the vector generator, the
   legacy engine, the differential tests and the BLAKE2b libsodium cross-check go; CI
   `crypto` job now builds `Derivation`; Dependabot entry; `docs/derivation.md`,
   `docs/recipe-format.md`, `docs/recipe-schema.json`; `docs/DEPENDENCIES.md` deleted (it
   exists to explain vendoring and subtrees, and nothing unusual remains; the Inconsolata
   origin goes to `THIRD_PARTY_LICENSES` if not already there, and the read-dicekey port
   note is already in `SCANNER-PORT-NOTES.md`); `ARCHITECTURE.md` and
   `THIRD_PARTY_LICENSES` updated; backlog item closed; this spec deleted.

## Docs

- `docs/recipe-format.md`: the harvested format, reduced to the table above, the salt-only
  fields, the canonical form rules, and the two word lists.
- `docs/derivation.md`: the construction, per-type derivation, output layouts, key formats,
  the compatibility contract, the legacy table, and the memory statement: secrets are Swift
  values with no zeroing or locking; the app keeps their lifetimes short, never logs them,
  and the pasteboard is local-only with a one-minute expiry.
- `docs/recipe-schema.json`: JSON Schema for the fields the package reads; a test checks
  every fixture recipe against it.
- `docs/BACKLOG.md`: already updated in its own PR (#17) before this sequence. The
  rewrite item is rewritten as done in PR 6, and the "Simpler recipes" item loses its web
  address sentence in PR 3.

## Out of scope

- Any new hash function or algorithm. The enum makes them contained follow-ups.
- The password screen changes.
- The `allow` field's object form. With hosts mode gone the app no longer writes `allow`.
- Zeroing secret memory.
