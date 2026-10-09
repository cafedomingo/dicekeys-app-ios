# Recipe format

A recipe is a string: either empty, or a JSON object. It is the second input to a
derivation, after the seed, and `Recipe` in `Packages/Derivation` is the parser.

The text is hashed exactly as given. Whitespace, key order, a byte order mark and fields the
format does not define all change the derived value, and the empty string and `{}` derive
different values. Everything below is about what the text means, never about how to rewrite
it.

## Fields

| Field | Type | Applies to | Default | Allowed |
|---|---|---|---|---|
| `type` | string | all | the requested type | must equal the requested type |
| `algorithm` | string | keys | per type | `XSalsa20Poly1305` for SymmetricKey, `X25519` for UnsealingKey, `Ed25519` for SigningKey; an error on Password and Secret |
| `hashFunction` | string | all | `BLAKE2b` | `BLAKE2b` |
| `lengthInBytes` | integer | Secret, keys | 32 | Secret: 1 to 8160; keys: 32 |
| `lengthInChars` | integer | Password | none | 1 or more; 1 to 1020 when it sizes a character set |
| `lengthInBits` | integer | Password | 128 | 1 or more, and the resolved word count must not exceed 1020 |
| `lengthInWords` | integer | Password | from bits | 1 to 1020 |
| `wordList` | string | Password | `EN_512_words_5_chars_max_ed_4_20200917` | one of the lists below |
| `separator` | string | Password; on a character set only `""` | none | `-`, ` `, `.`, `,`, `_`, `""` or `digits` |
| `capitalize` | boolean | Password, with `separator` | false | true or false |

A field that applies to another type is not read, except `algorithm`. `wordList` on a Secret
is ignored; `hashFunction`, `type` and `algorithm` are checked for every type. On a Password,
`lengthInBytes` must still be an integer, but it is then overridden: the derived length is
the resolved word count times 8.

`recipe-schema.json` describes the fields above as a JSON Schema.

## Salt only

Any other field is salt: it changes the derived value because it is part of the text, and
nothing reads it. The format defines these names, and this app never acts on them: `allow`,
`excludeOrientationOfFaces`, `clientMayRetrieveKey`, `requireAuthenticationHandshake`,
`androidPackagePrefixesAllowed`, `requireUsersConsent`, `hashFunctionMemoryLimitInBytes` and
`hashFunctionMemoryPasses`.

The app writes two more. `purpose` is the label of a recipe, and `#` is its sequence number,
written only when it is above 1 so that changing it derives a new secret. `Derivation` does
not read either. The app reads `purpose` to choose the output shown first for a signing key
or secret (`pgp`, `ssh` or `wallet`).

## Validation

- Integer fields must be JSON integers. Fractions, exponents, booleans, strings and null are
  `wrongType`; an integer too large for `Int` is `outOfRange`.
- A name that appears twice in one object is `duplicateField`.
- Given together, `lengthInWords` must equal the fewest words whose list-size power reaches
  2^`lengthInBits`, or the recipe is `bitsAndWordsConflict`. For a power-of-two list that is
  `ceil(bits / log2(size))`.
- A Password resolves its length in this order: if neither bits nor words is given, then on
  a character-set list with `lengthInChars` the word count is `lengthInChars` (1 to 1020),
  otherwise bits is 128; if only bits is given, words follow from bits; if only words is
  given, it stands. Then `lengthInBytes` is words times 8.
- `separator` and `capitalize` are read on word lists. `capitalize` without `separator` is
  `invalidJoining`. On a character-set list a `separator` other than `""` or a `capitalize`
  of true is `invalidJoining`. An unknown separator is `unknownSeparator`.
- Unless it sizes a character set, `lengthInChars` truncates the finished password, the word
  count prefix included.
- A key with a `lengthInBytes` other than 32 is `lengthMustBe32`.
- The upper bounds (8160 bytes, 1020 words) are the HKDF limit of 255 blocks of 32 bytes.
- The text must be strict JSON, apart from a leading byte order mark, which the parser skips
  and the hash still includes.
- Nesting deeper than 128 levels is `invalidJson`.
- Whitespace-only text, or valid JSON that is not an object, is `recipeNotAnObject`; any
  other text that is not valid JSON is `invalidJson`.

An unknown `hashFunction`, `wordList` or `algorithm` is an error rather than a fallback.
The name is part of the text that gets hashed, so a recipe naming something this app does
not implement would otherwise derive a value that no implementation of the format would
reproduce, and the user would only find out when another app disagreed.

## Canonical form

The recipe builder and the raw JSON editor write recipes in the form
`RecipeJsonValue.canonicalText` produces, which matches the DiceKeys TypeScript app's
`canonicalizeRecipeJson`:

- no whitespace outside strings;
- object fields sorted by UTF-16 code unit at every level, with `purpose` first and `#` last;
- numbers and string values kept as their source text; booleans and null as themselves;
- field names written decoded, and a name whose decoded text holds a quote, a backslash or a
  control character rejected;
- duplicate names rejected;
- nesting limited to 128 levels;
- input that is not a JSON object rejected.

`Derivation` never rewrites a recipe: it hashes the text it is given, canonical or not.

This is not RFC 8785 (JSON Canonicalization Scheme), which would be the choice for a format
starting fresh. JCS sorts every key by UTF-16 code unit with no exceptions, re-serializes
numbers as ECMAScript does (`1.0` becomes `1`) and re-escapes strings minimally. The
reference form puts `purpose` first and `#` last and keeps numbers and strings as typed.
Because the text is the salt, moving to JCS would change the derived value of nearly every
recipe and silently break the promise that any DiceKeys app derives the same secrets from the
same dice, so the form stays the reference's unless the ecosystem moves together.

## Word lists

| Name | Entries | Kind | Bits per entry |
|---|---|---|---|
| `EN_512_words_5_chars_max_ed_4_20200917` | 512 | words | 9 |
| `EN_1024_words_6_chars_max_ed_4_20200917` | 1024 | words | 10 |
| `EFF_large_7776_words_9_chars_max_20160719` | 7776 | words | 12.925 |
| `EMOJI_512_single_code_point_20261002` | 512 | characters | 9 |
| `CHARS_67_letters_digits_symbols_20261002` | 67 | characters | 6.066 |
| `CHARS_57_letters_digits_20261002` | 57 | characters | 5.833 |
| `CHARS_59_letters_symbols_20261002` | 59 | characters | 5.883 |
| `CHARS_49_letters_20261002` | 49 | characters | 5.615 |
| `CHARS_10_digits_20261002` | 10 | characters | 3.322 |

The first two are the reference's, in `WordLists.swift`, in the order the reference used. The
rest are this app's: `WordLists+EFF.swift` and `WordLists+Emoji.swift` are generated by
`scripts/generate-wordlists.py` and `CharacterSets.swift` is literal. Letters omit I, O and l,
and the digits beside letters omit 0 and 1; symbols are `!@#$%&*-_?`. Every order is part of
the format.

A list's kind decides the unit of length and the joining. Words take separators,
capitalization and a length in words. Characters, emoji included, are concatenated and take
their length in characters.

## Joining

Without `separator`, a password is joined as the reference joined it: the decimal word
count, then a hyphen and a word each, the first word's first letter uppercased. With
`separator`, there is no count, the words are joined by the separator, and all are lowercase
except that `capitalize` uppercases one whole word. The words are the same either way.

Each word is its 8-byte block modulo the list size. The block's quotient by the list size is
independent of that remainder and supplies the rest: with `separator` `digits`, the digit
after word `i` is block `i`'s quotient modulo 10; with `capitalize`, the uppercased word is
at index (last block's quotient modulo the word count). `lengthInChars` truncates the
finished string in either joining, counting one per character, so one per emoji.
