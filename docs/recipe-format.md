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
| `lengthInChars` | integer | Password | none | 1 or more |
| `lengthInBits` | integer | Password | 128 | 1 or more, and the resolved word count must not exceed 1020 |
| `lengthInWords` | integer | Password | from bits | 1 to 1020 |
| `wordList` | string | Password | `EN_512_words_5_chars_max_ed_4_20200917` | one of the two word lists below |

A field that applies to another type is not read. `wordList` on a Secret is ignored;
`hashFunction` and `type` are checked for every type. On a Password, `lengthInBytes` must
still be an integer, but it is then overridden: the derived length is the resolved word
count times 8.

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
- Given together, `lengthInWords` must equal `ceil(lengthInBits / bitsPerWord)`, or the
  recipe is `bitsAndWordsConflict`. `bitsPerWord` is 9 for the 512-word list and 10 for the
  1024-word list.
- A Password resolves its length in this order: if neither bits nor words is given, bits is
  128; if only bits is given, words is `ceil(bits / bitsPerWord)`; if only words is given,
  it stands. Then `lengthInBytes` is words times 8.
- `lengthInChars` truncates the finished password, the word count prefix included.
- A key with a `lengthInBytes` other than 32 is `lengthMustBe32`.
- The upper bounds (8160 bytes, 1020 words) are the HKDF limit of 255 blocks of 32 bytes.
- The text must be strict JSON, apart from a leading byte order mark, which the parser skips and the hash still includes. Nesting deeper than 128 levels is `invalidJson`.
- Text that is not a JSON object, whitespace-only text included, is `recipeNotAnObject`.

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

## Word lists

| Name | Words | Bits per word |
|---|---|---|
| `EN_512_words_5_chars_max_ed_4_20200917` | 512 | 9 |
| `EN_1024_words_6_chars_max_ed_4_20200917` | 1024 | 10 |

The names are the format's; the lists are in `WordLists.swift`, in the order the reference
implementation used, and that order is part of the format.
