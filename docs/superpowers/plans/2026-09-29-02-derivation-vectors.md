# Derivation Vectors Implementation Plan (PR 2 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record, from the vendored C++ while it still exists, every derivation output the Swift port must reproduce, every legacy behavior it will reject or change, and every recipe the C++ rejects, as one fixture the package tests read.

**Architecture:** A C++ generator linked against the vendored libsodium, lib-seeded and the C ABI shim enumerates a case matrix (four DiceKeys with and without orientations, every template, every length bound, text variants, type and algorithm fields, legacy quirks, rejections) and writes `vectors.json` with three sections: `cases`, `legacy` and `rejected`. The existing `GoldenVectorTests` is replaced by `VectorTests`, which derives every `cases` and `legacy` entry through the current Swift API and expects every `rejected` entry to throw. The app's seed tests gain the three new DiceKeys.

**Tech Stack:** clang/clang++ (Xcode's), nlohmann/json (already vendored under lib-seeded), Swift Testing, `swift test` for the package, xcodebuild for the app tests.

**Spec:** `docs/superpowers/specs/2026-09-29-derivation-rewrite-design.md`, sections "Compatibility contract", "Legacy behaviors", "Testing: Fixture" and "PR sequence" item 2.

## Global Constraints

- No product code changes in this PR. The fixture, the generator, and tests only.
- The fixture is generated, never hand-edited. Any change to it must come from re-running `scripts/generate-vectors.sh`.
- Package tests run as CI does: `cd Packages/SeededCrypto && swift test -c release -Xswiftc -enable-testing --parallel`, with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` exported.
- App tests as in plan 01 (`xcodebuild test ... -only-testing:DiceKeysTests/DiceKeySeedTests`).
- `shellcheck scripts/*.sh` must pass (CI runs it).
- American spelling; no em-dashes; no attribution trailers; comments explain why, not what changed.
- Branch: `derivation-vectors`, created from `origin/main` in a fresh worktree (`git worktree add .claude/worktrees/derivation-vectors -b derivation-vectors origin/main`). This PR does not depend on PR 1.

## Review Focus

Inputs the spec implies that need a pinned case in the fixture, each placed in the task that owns it:

1. A recipe of exactly `{}` versus the empty string must produce different outputs for the same type and seed (the C++ hashes the raw text). Task 1, group B.
2. A recipe with a UTF-8 byte order mark must derive and differ from the same recipe without it. Task 1, group D.
3. `lengthInBytes` of exactly 8160 must derive; 8192 is recorded as legacy because the port rejects it. Task 1, groups C and G.
4. A signing key exported with a non-empty OpenSSH comment and a non-empty PGP user ID with a non-zero timestamp must be recorded, since the port compares those exports by parsed content. Task 1, group H.
5. The four DiceKeys' seeds must equal what `DiceKey.toSeed()` computes from their human-readable forms, with and without orientations, or the fixture would silently test seeds no DiceKey produces. Task 3.

---

## File Structure

- Create `scripts/generate-vectors.cpp`: the case matrix and the JSON writer. Replaces `scripts/generate-golden-vectors.cpp` (deleted).
- Create `scripts/generate-vectors.sh`: builds and runs it. Replaces `scripts/generate-golden-vectors.sh` (deleted).
- Create `Packages/SeededCrypto/Tests/SeededCryptoTests/Fixtures/vectors.json` (generated). Delete `golden-vectors.json`.
- Create `Packages/SeededCrypto/Tests/SeededCryptoTests/VectorTests.swift`. Delete `GoldenVectorTests.swift`.
- Modify `Packages/SeededCrypto/Tests/SeededCryptoTests/EmptyRecipeTests.swift:17,25`: it reads `fixture.exampleDiceKeySeed`, which moves.
- Modify `Tests/DiceKeysTests/DiceKeySeedTests.swift`: three more DiceKeys.
- Modify `docs/ARCHITECTURE.md:201-202`, `docs/DEPENDENCIES.md:4`, `Tests/DiceKeysTests/PasswordDerivationTests.swift:21`: file names.

## Fixture format

```json
{
  "sodiumVersion": "1.0.22",
  "diceKeys": [
    {"name": "example", "humanReadableForm": "...", "seed": "...75 chars...", "seedWithoutOrientations": "...50 chars..."}
  ],
  "cases": [ <vector> ],
  "legacy": [ <vector with "note"> ],
  "rejected": [ {"name", "seed", "type", "recipe", "note"?, "error": "<C++ what()>"} ]
}
```

A `<vector>` has `name`, `seed`, `type`, `recipe`, `json` (the object's `toJson()`), and by type: `password`; `secretBytesHex`; `keyBytesHex`; `sealingKeyBytesHex` and `unsealingKeyBytesHex`; or `signingKeyBytesHex`, `openSshPublicKey`, `sshComment`, `openSshPemPrivateKey`, `pgpUserId`, `pgpTimestamp`, `openPgpPemFormatSecretKey`. Keys inside each object are in alphabetical order because nlohmann sorts them.

The four DiceKeys (human-readable form, canonical seed, canonical seed without orientations), computed with the same rotation and ordering rules as `DiceKey.toSeed()` and checked against the example key's known seed:

| name | humanReadableForm | seed | seedWithoutOrientations |
|---|---|---|---|
| example | `A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t` | same | `A1B2C3D4E5F6G1H2I3J4K5L6M1N2O3P4R5S6T1U2V3W4X5Y6Z1` |
| second | `F2lY4rC2bV6bX4rK1rD5lS4bG6bZ2lU4rA6tI5bB1lT3rP3lL6lH6lN2tE2rO2rW1tJ5lR1tM2b` | same | `F2Y4C2V6X4K1D5S4G6Z2U4A6I5B1T3P3L6H6N2E2O2W1J5R1M2` |
| third | `I5lW5tZ5tY2tD3rU1lX3bB4bA2bL2lC1lO1tP1tM2bS1lT1bR3lN2lJ3lE2rF3rG3rV5tH1lK3r` | `D3tL2bS1bE2tK3tY2lA2rM2rJ3bH1bZ5lB4rP1lN2bV5lW5lX3rO1lR3bG3tI5bU1bC1bT1rF3t` | `D3L2S1E2K3Y2A2M2J3H1Z5B4P1N2V5W5X3O1R3G3I5U1C1T1F3` |
| fourth | `N1rO6lX2tZ1lY5rA6rR1lE6bD2bM3bB4tP1tC6lU1tI3rK1tL6lW1rH1rJ2lF5lV4lT2rS4bG2l` | `F5tK1rB4rA6bN1bV4tL6tP1rR1tO6tT2bW1bC6tE6lX2rS4lH1bU1rD2lZ1tG2tJ2tI3bM3lY5b` | `F5K1B4A6N1V4L6P1R1O6T2W1C6E6X2S4H1U1D2Z1G2J2I3M3Y5` |

"second" happens to already be in canonical rotation; "third" and "fourth" are not, which is what makes them worth having. Task 3 proves all four against the app.

---

### Task 1: The generator

**Files:**
- Create: `scripts/generate-vectors.cpp`
- Create: `scripts/generate-vectors.sh`
- Delete: `scripts/generate-golden-vectors.cpp`, `scripts/generate-golden-vectors.sh`

**Interfaces:**
- Produces: `Packages/SeededCrypto/Tests/SeededCryptoTests/Fixtures/vectors.json` in the format above.

- [ ] **Step 1: Write the build script**

Create `scripts/generate-vectors.sh`:

```bash
#!/usr/bin/env bash
# Regenerates the derivation vectors from the vendored reference C++. It is the only
# reference implementation of DiceKeys derivation, so everything the Swift port must
# reproduce is captured here while the C++ still exists. A diff in the output after a
# libsodium or lib-seeded change means derived secrets changed, which is almost always a bug.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/Packages/SeededCrypto/Sources"
BUILD="$ROOT/.build/vectors"
OUT="$ROOT/Packages/SeededCrypto/Tests/SeededCryptoTests/Fixtures/vectors.json"
# Every object is rebuilt and every object in the directory is linked, so start empty: objects
# left from a checkout at another path would be linked twice.
rm -rf "$BUILD"
mkdir -p "$BUILD"
CFLAGS=(-O1 -w -DNATIVE_LITTLE_ENDIAN=1 -DHAVE_MADVISE -DHAVE_MMAP -DHAVE_MPROTECT -DHAVE_POSIX_MEMALIGN -DHAVE_WEAK_SYMBOLS -DCONFIGURED=1)
while IFS= read -r -d '' f; do
  clang "${CFLAGS[@]}" -I"$PKG/CSodium/include" -I"$PKG/CSodium/include/sodium" -c "$f" -o "$BUILD/$(echo "$f" | tr '/' '_').o"
done < <(find "$PKG/CSodium" -name '*.c' -print0)
LIB="$ROOT/Packages/SeededCrypto/Vendor/seeded-crypto/lib-seeded"
while IFS= read -r -d '' f; do
  clang++ -std=c++17 -O1 -w -I"$LIB" -I"$PKG/SeededCryptoNative/include" -I"$PKG/CSodium/include" -c "$f" -o "$BUILD/$(basename "$f").o"
done < <(find "$LIB" "$PKG/SeededCryptoNative" -name '*.cpp' -print0)
clang++ -std=c++17 -O1 -w -I"$LIB" -I"$PKG/SeededCryptoNative/include" "$ROOT/scripts/generate-vectors.cpp" "$BUILD"/*.o -o "$BUILD/generate-vectors"
"$BUILD/generate-vectors" > "$OUT"
echo "Wrote ${OUT#"$ROOT"/}"
```

Delete `scripts/generate-golden-vectors.sh` and `scripts/generate-golden-vectors.cpp`.

- [ ] **Step 2: Write the generator**

Create `scripts/generate-vectors.cpp`:

```cpp
// Generates Packages/SeededCrypto/Tests/SeededCryptoTests/Fixtures/vectors.json from the
// reference C++ (lib-seeded + libsodium) through the C ABI shim. Three sections:
//   cases     what every implementation must reproduce byte for byte
//   legacy    what the C++ produced for inputs the Swift port rejects or handles differently,
//             kept so the old behavior can be restored and verified
//   rejected  inputs the C++ refuses, with its message
// Build and run with scripts/generate-vectors.sh.
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>
#include "SeededCryptoNative.h"
#include "github-com-nlohmann-json/json.hpp"

using nlohmann::json;

static std::string take(char *s) { std::string r = s ? s : ""; dkc_free(s); return r; }

[[noreturn]] static void fail(const std::string &name, const std::string &why) {
    fprintf(stderr, "%s: %s\n", name.c_str(), why.c_str());
    exit(1);
}

struct DiceKey { std::string name, humanReadableForm, seed, seedWithoutOrientations; };

// The example key from DiceKey.Example plus three fixed keys. "third" and "fourth" are not
// in canonical rotation as written, so their seeds differ from their human-readable forms.
static const std::vector<DiceKey> diceKeys = {
    {"example",
     "A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t",
     "A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t",
     "A1B2C3D4E5F6G1H2I3J4K5L6M1N2O3P4R5S6T1U2V3W4X5Y6Z1"},
    {"second",
     "F2lY4rC2bV6bX4rK1rD5lS4bG6bZ2lU4rA6tI5bB1lT3rP3lL6lH6lN2tE2rO2rW1tJ5lR1tM2b",
     "F2lY4rC2bV6bX4rK1rD5lS4bG6bZ2lU4rA6tI5bB1lT3rP3lL6lH6lN2tE2rO2rW1tJ5lR1tM2b",
     "F2Y4C2V6X4K1D5S4G6Z2U4A6I5B1T3P3L6H6N2E2O2W1J5R1M2"},
    {"third",
     "I5lW5tZ5tY2tD3rU1lX3bB4bA2bL2lC1lO1tP1tM2bS1lT1bR3lN2lJ3lE2rF3rG3rV5tH1lK3r",
     "D3tL2bS1bE2tK3tY2lA2rM2rJ3bH1bZ5lB4rP1lN2bV5lW5lX3rO1lR3bG3tI5bU1bC1bT1rF3t",
     "D3L2S1E2K3Y2A2M2J3H1Z5B4P1N2V5W5X3O1R3G3I5U1C1T1F3"},
    {"fourth",
     "N1rO6lX2tZ1lY5rA6rR1lE6bD2bM3bB4tP1tC6lU1tI3rK1tL6lW1rH1rJ2lF5lV4lT2rS4bG2l",
     "F5tK1rB4rA6bN1bV4tL6tP1rR1tO6tT2bW1bC6tE6lX2rS4lH1bU1rD2lZ1tG2tJ2tI3bM3lY5b",
     "F5K1B4A6N1V4L6P1R1O6T2W1C6E6X2S4H1U1D2Z1G2J2I3M3Y5"},
};

struct Template { std::string name, type, recipe; };

// DerivationRecipeTemplates.swift, verbatim.
static const std::vector<Template> templates = {
    {"1Password", "Password", R"({"allow":[{"host":"*.1password.com"}]})"},
    {"Apple", "Password", R"({"allow":[{"host":"*.apple.com"},{"host":"*.icloud.com"}],"lengthInChars":64})"},
    {"Authy", "Password", R"({"allow":[{"host":"*.authy.com"}]})"},
    {"Bitwarden", "Password", R"({"allow":[{"host":"*.bitwarden.com"}]})"},
    {"Facebook", "Password", R"({"allow":[{"host":"*.facebook.com"}]})"},
    {"Google", "Password", R"({"allow":[{"host":"*.google.com"}]})"},
    {"Keeper", "Password", R"({"allow":[{"host":"*.keepersecurity.com"},{"host":"*.keepersecurity.eu"}]})"},
    {"LastPass", "Password", R"({"allow":[{"host":"*.lastpass.com"}]})"},
    {"Microsoft", "Password", R"({"allow":[{"host":"*.microsoft.com"},{"host":"*.live.com"}]})"},
    {"SSH", "SigningKey", R"({"purpose":"ssh"})"},
    {"PGP", "SigningKey", R"({"purpose":"pgp"})"},
    {"wallet", "Secret", R"({"purpose":"wallet"})"},
};

struct Case {
    std::string section, name, type, seed, recipe, note;
    std::string sshComment, pgpUserId;
    uint32_t pgpTimestamp = 0;
};

static std::vector<Case> cases;

static void add(const std::string &section, const std::string &name, const std::string &type,
                const std::string &seed, const std::string &recipe, const std::string &note = "") {
    cases.push_back({section, name, type, seed, recipe, note});
}

static const std::string &example = diceKeys[0].seed;
static const std::vector<std::string> allTypes = {"Password", "Secret", "SymmetricKey", "UnsealingKey", "SigningKey"};

static void buildCases() {
    // A. Every template on every seed, with and without orientations.
    for (auto &k : diceKeys) {
        for (auto &t : templates) {
            add("cases", "template " + t.name + " / " + k.name, t.type, k.seed, t.recipe);
            add("cases", "template " + t.name + " / " + k.name + " without orientations", t.type, k.seedWithoutOrientations, t.recipe);
        }
    }
    // B. The empty recipe and the empty object are different inputs.
    for (auto &type : allTypes) {
        add("cases", "empty recipe / " + type, type, example, "");
        add("cases", "empty object / " + type, type, example, "{}");
        add("cases", "empty recipe / " + type + " / second", type, diceKeys[1].seed, "");
    }
    // C. Length fields at their bounds.
    for (int n : {1, 2, 16, 31, 32, 33, 64, 8160}) {
        add("cases", "secret lengthInBytes " + std::to_string(n), "Secret", example, R"({"lengthInBytes":)" + std::to_string(n) + "}");
    }
    add("cases", "symmetric key lengthInBytes 32 explicit", "SymmetricKey", example, R"({"lengthInBytes":32})");
    add("cases", "unsealing key lengthInBytes 32 explicit", "UnsealingKey", example, R"({"lengthInBytes":32})");
    add("cases", "signing key lengthInBytes 32 explicit", "SigningKey", example, R"({"lengthInBytes":32})");
    for (int n : {1, 2, 15, 1020}) {
        add("cases", "password lengthInWords " + std::to_string(n), "Password", example, R"({"lengthInWords":)" + std::to_string(n) + "}");
    }
    for (int n : {1, 9, 10, 90, 128, 9180}) {
        add("cases", "password lengthInBits " + std::to_string(n), "Password", example, R"({"lengthInBits":)" + std::to_string(n) + "}");
    }
    for (int n : {1, 8, 9, 16, 64, 100}) {
        add("cases", "password lengthInChars " + std::to_string(n), "Password", example, R"({"lengthInChars":)" + std::to_string(n) + "}");
    }
    add("cases", "password wordList 1024", "Password", example, R"({"wordList":"EN_1024_words_6_chars_max_ed_4_20200917"})");
    add("cases", "password wordList 1024 lengthInWords 3", "Password", example, R"({"wordList":"EN_1024_words_6_chars_max_ed_4_20200917","lengthInWords":3})");
    add("cases", "password wordList 1024 lengthInBits 1", "Password", example, R"({"wordList":"EN_1024_words_6_chars_max_ed_4_20200917","lengthInBits":1})");
    add("cases", "password wordList 512 explicit", "Password", example, R"({"wordList":"EN_512_words_5_chars_max_ed_4_20200917"})");
    add("cases", "password lengthInChars and lengthInWords", "Password", example, R"({"lengthInWords":4,"lengthInChars":10})");
    // D. The recipe text is the salt: whitespace, order, a BOM, unknown and salt-only fields.
    const std::vector<std::pair<std::string, std::string>> texts = {
        {"plain", R"({"purpose":"x"})"},
        {"leading space", R"( {"purpose":"x"})"},
        {"trailing space", R"({"purpose":"x"} )"},
        {"trailing newline", "{\"purpose\":\"x\"}\n"},
        {"inner whitespace", R"({ "purpose" : "x" })"},
        {"byte order mark", "\xEF\xBB\xBF{\"purpose\":\"x\"}"},
        {"sequence after purpose", R"({"purpose":"x","#":2})"},
        {"sequence before purpose", R"({"#":2,"purpose":"x"})"},
        {"unknown field", R"({"purpose":"x","zzz":1})"},
        {"nested object", R"({"purpose":"x","meta":{"a":[1,2,{"b":null}]}})"},
        {"non-ascii", "{\"purpose\":\"caf\xC3\xA9\"}"},
        {"escapes", R"({"purpose":"a\"b\\c\/dé"})"},
        {"memory fields under BLAKE2b are salt", R"({"purpose":"x","hashFunctionMemoryLimitInBytes":8192,"hashFunctionMemoryPasses":9})"},
        {"excludeOrientationOfFaces is salt", R"({"purpose":"x","excludeOrientationOfFaces":true})"},
        {"authorization fields are salt", R"({"purpose":"x","allow":[{"host":"*.example.com","paths":["/a"]}],"clientMayRetrieveKey":true,"requireAuthenticationHandshake":true})"},
    };
    for (auto &t : texts) add("cases", "text: " + t.first, "Secret", example, t.second);
    // E. type, algorithm and hashFunction present and matching.
    add("cases", "type Password", "Password", example, R"({"type":"Password"})");
    add("cases", "type Secret lengthInBytes 16", "Secret", example, R"({"type":"Secret","lengthInBytes":16})");
    add("cases", "type and algorithm SymmetricKey", "SymmetricKey", example, R"({"type":"SymmetricKey","algorithm":"XSalsa20Poly1305"})");
    add("cases", "type and algorithm UnsealingKey", "UnsealingKey", example, R"({"type":"UnsealingKey","algorithm":"X25519"})");
    add("cases", "type and algorithm SigningKey", "SigningKey", example, R"({"type":"SigningKey","algorithm":"Ed25519"})");
    add("cases", "hashFunction BLAKE2b explicit", "Secret", example, R"({"hashFunction":"BLAKE2b"})");
    // H. Signing key exports with the optional inputs set.
    {
        Case c{"cases", "signing key exports with comment, user id and timestamp", "SigningKey", example, R"({"purpose":"exports"})", ""};
        c.sshComment = "alice@laptop";
        c.pgpUserId = "Alice Example <alice@example.com>";
        c.pgpTimestamp = 1700000000;
        cases.push_back(c);
    }
    // F. Rejected by the C++.
    add("rejected", "type mismatch", "Password", example, R"({"type":"Secret"})");
    add("rejected", "wrong algorithm for SymmetricKey", "SymmetricKey", example, R"({"algorithm":"X25519"})");
    add("rejected", "wrong algorithm for SigningKey", "SigningKey", example, R"({"algorithm":"X25519"})");
    add("rejected", "signing key lengthInBytes 16", "SigningKey", example, R"({"lengthInBytes":16})");
    add("rejected", "unknown hashFunction", "Secret", example, R"({"hashFunction":"SHA256"})");
    add("rejected", "array recipe", "Secret", example, "[]");
    add("rejected", "string recipe", "Secret", example, R"("x")");
    add("rejected", "invalid json", "Password", example, "{not json");
    add("rejected", "lengthInBytes as string", "Secret", example, R"({"lengthInBytes":"16"})");
    add("rejected", "lengthInBytes null", "Secret", example, R"({"lengthInBytes":null})");
    add("rejected", "consistent lengthInBits and lengthInWords", "Password", example, R"({"lengthInBits":90,"lengthInWords":10})",
        "The C++ check multiplies where it should divide, so it rejects this correct pair. The port accepts it.");
    add("rejected", "key algorithm on a Password", "Password", example, R"({"algorithm":"X25519"})",
        "The C++ forces lengthInBytes 32 for a key algorithm even on a Password, whose length is 120. The port rejects any algorithm on a Password.");
    // G. Legacy: derived by the C++, rejected or changed by the port.
    add("legacy", "argon2id defaults", "Secret", example, R"({"hashFunction":"Argon2id"})",
        "Argon2id via libsodium's internal argon2id_hash_raw: salt = type string + recipe, lanes 1, 2 passes, 64 MiB. The port throws unsupportedHashFunction.");
    add("legacy", "argon2id lengthInBytes 8", "Secret", example, R"({"hashFunction":"Argon2id","lengthInBytes":8})",
        "Output shorter than Argon2's 16-byte minimum is the first 8 bytes of the 16-byte hash.");
    add("legacy", "argon2id lengthInBytes 96", "Secret", example, R"({"hashFunction":"Argon2id","lengthInBytes":96})",
        "Output longer than 64 bytes exercises Argon2's variable-length H' construction.");
    add("legacy", "argon2id small memory one pass", "Secret", example, R"({"hashFunction":"Argon2id","hashFunctionMemoryLimitInBytes":8388608,"hashFunctionMemoryPasses":1})",
        "Memory 8 MiB, one pass.");
    add("legacy", "argon2id password", "Password", example, R"({"hashFunction":"Argon2id"})",
        "Argon2id feeding the password word selection.");
    add("legacy", "lengthInBytes fractional", "Secret", example, R"({"lengthInBytes":16.9})",
        "nlohmann truncated 16.9 to 16. The port throws wrongType.");
    add("legacy", "lengthInBytes boolean", "Secret", example, R"({"lengthInBytes":true})",
        "nlohmann read true as 1. The port throws wrongType.");
    add("legacy", "lengthInBytes 0", "Secret", example, R"({"lengthInBytes":0})",
        "An empty secret. The port throws outOfRange.");
    add("legacy", "lengthInChars 0", "Password", example, R"({"lengthInChars":0})",
        "An empty password (upstream issue 56). The port throws outOfRange.");
    add("legacy", "issue 56 seed", "Password", "this string is seedy", R"({"allow":[{"host":"*.exampl.com"}],"lengthInChars":0})",
        "The original issue 56 vector, kept for the app's PasswordDerivationTests until the port lands.");
    add("legacy", "unknown wordList", "Password", example, R"({"wordList":"nonsense"})",
        "Fell back to the 512 list. The port throws unknownWordList.");
    add("legacy", "inverted bits and words check accepts a wrong pair", "Password", example, R"({"lengthInBits":1,"lengthInWords":9})",
        "Accepted because 9 == ceil(1 * 9); lengthInWords wins. The port throws bitsAndWordsConflict.");
    add("legacy", "duplicate lengthInBytes", "Secret", example, R"({"lengthInBytes":16,"lengthInBytes":8})",
        "nlohmann kept the last value. The port throws duplicateField.");
    add("legacy", "key algorithm on a Secret", "Secret", example, R"({"algorithm":"X25519"})",
        "Tolerated, forcing lengthInBytes 32. The port throws invalidAlgorithm.");
    add("legacy", "unknown algorithm on a Password", "Password", example, R"({"algorithm":"bogus"})",
        "Any unknown algorithm was ignored on a Password. The port throws invalidAlgorithm.");
    add("legacy", "lengthInBytes 8192 past the HKDF limit", "Secret", example, R"({"lengthInBytes":8192})",
        "The one-byte HKDF counter wrapped after 255 blocks. The port allows at most 8160.");
    add("legacy", "lengthInWords 1021 past the HKDF limit", "Password", example, R"({"lengthInWords":1021})",
        "8168 bytes of words. The port allows at most 1020 words.");
    add("legacy", "lengthInBytes above 32 bits", "Secret", example, R"({"lengthInBytes":4294967312})",
        "Truncated to 32 bits, so 16. The port throws outOfRange.");
}

static json derive(const Case &c, bool &ok) {
    json v;
    v["name"] = c.name;
    v["seed"] = c.seed;
    v["type"] = c.type;
    v["recipe"] = c.recipe;
    if (!c.note.empty()) v["note"] = c.note;
    char *j = nullptr, *err = nullptr, *s = nullptr;
    int (*deriveFn)(const char *, const char *, char **, char **) =
        c.type == "Password" ? dkc_password_derive :
        c.type == "Secret" ? dkc_secret_derive :
        c.type == "SymmetricKey" ? dkc_symmetric_key_derive :
        c.type == "UnsealingKey" ? dkc_unsealing_key_derive : dkc_signing_key_derive;
    ok = deriveFn(c.seed.c_str(), c.recipe.c_str(), &j, &err) == 1;
    if (!ok) { v["error"] = take(err); return v; }
    std::string js = take(j);
    v["json"] = js;
    json parsed = json::parse(js);
    if (c.type == "Password") {
        v["password"] = parsed["password"];
    } else if (c.type == "Secret") {
        v["secretBytesHex"] = parsed["secretBytes"];
    } else if (c.type == "SymmetricKey") {
        v["keyBytesHex"] = parsed["keyBytes"];
    } else if (c.type == "UnsealingKey") {
        v["sealingKeyBytesHex"] = parsed["sealingKeyBytes"];
        v["unsealingKeyBytesHex"] = parsed["unsealingKeyBytes"];
    } else {
        v["signingKeyBytesHex"] = parsed["signingKeyBytes"];
        if (!dkc_signing_key_open_ssh_public_key(js.c_str(), &s, &err)) fail(c.name, take(err));
        v["openSshPublicKey"] = take(s);
        if (!dkc_signing_key_open_ssh_pem_private_key(js.c_str(), c.sshComment.c_str(), &s, &err)) fail(c.name, take(err));
        v["sshComment"] = c.sshComment;
        v["openSshPemPrivateKey"] = take(s);
        if (!dkc_signing_key_open_pgp_pem_secret_key(js.c_str(), c.pgpUserId.c_str(), c.pgpTimestamp, &s, &err)) fail(c.name, take(err));
        v["pgpUserId"] = c.pgpUserId;
        v["pgpTimestamp"] = c.pgpTimestamp;
        v["openPgpPemFormatSecretKey"] = take(s);
    }
    return v;
}

int main() {
    buildCases();
    json out;
    out["sodiumVersion"] = dkc_sodium_version();
    json keys = json::array();
    for (auto &k : diceKeys) {
        keys.push_back({{"name", k.name}, {"humanReadableForm", k.humanReadableForm},
                        {"seed", k.seed}, {"seedWithoutOrientations", k.seedWithoutOrientations}});
    }
    out["diceKeys"] = keys;
    json sections = {{"cases", json::array()}, {"legacy", json::array()}, {"rejected", json::array()}};
    for (auto &c : cases) {
        bool ok = false;
        json v = derive(c, ok);
        bool expectOk = c.section != "rejected";
        if (ok != expectOk) fail(c.name, ok ? "derived, but was expected to be rejected" : "rejected: " + v["error"].get<std::string>());
        sections[c.section].push_back(v);
    }
    for (auto &section : {"cases", "legacy", "rejected"}) out[section] = sections[section];
    printf("%s\n", out.dump(2).c_str());
    return 0;
}
```

- [ ] **Step 3: Generate the fixture**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
shellcheck scripts/*.sh
./scripts/generate-vectors.sh
rm Packages/SeededCrypto/Tests/SeededCryptoTests/Fixtures/golden-vectors.json
python3 -c "import json; d=json.load(open('Packages/SeededCrypto/Tests/SeededCryptoTests/Fixtures/vectors.json')); print({k: len(d[k]) for k in ('cases','legacy','rejected')})"
```
Expected: shellcheck silent; the script prints `Wrote Packages/...vectors.json`; the counts are `{'cases': 165, 'legacy': 19, 'rejected': 12}` (96 template + 15 empty + 32 length + 15 text + 6 type and algorithm + 1 exports = 165). If the generator exits with a "rejected:" or "derived, but" message, the case's section is wrong: fix the case list, not the expectation, unless the message shows the C++ genuinely behaves differently from the spec's description, in which case record what it does in the `note` and move the case to the section that matches.

Spot-check three values against the old fixture, which is still in git history (`git show HEAD:Packages/SeededCrypto/Tests/SeededCryptoTests/Fixtures/golden-vectors.json`): "template 1Password / example" must have password `15-Self-depth-yahoo-limbs-brute-petty-ionic-fool-await-spree-ought-vixen-happy-runny-blend`; "template wallet / example" secretBytesHex `d19e149109f0d77657fc39d91583c9a2b8f392a71a20b0bb0f3f67f3d0455480`; "issue 56 seed" password empty.

- [ ] **Step 4: Commit**

```bash
git add scripts/generate-vectors.sh scripts/generate-vectors.cpp Packages/SeededCrypto/Tests/SeededCryptoTests/Fixtures/vectors.json
git rm scripts/generate-golden-vectors.sh scripts/generate-golden-vectors.cpp Packages/SeededCrypto/Tests/SeededCryptoTests/Fixtures/golden-vectors.json
git commit -m "Record the derivation vectors the Swift port must reproduce"
```

The package tests do not compile at this commit (`GoldenVectorTests` reads the old fixture); Task 2 fixes that before the PR.

---

### Task 2: The package tests read the new fixture

**Files:**
- Create: `Packages/SeededCrypto/Tests/SeededCryptoTests/VectorTests.swift`
- Delete: `Packages/SeededCrypto/Tests/SeededCryptoTests/GoldenVectorTests.swift`
- Modify: `Packages/SeededCrypto/Tests/SeededCryptoTests/EmptyRecipeTests.swift:17,25`

**Interfaces:**
- Consumes: `vectors.json` as in "Fixture format".
- Produces: `let fixture: VectorFixture` (module-level, used by `EmptyRecipeTests`), `struct Vector`, `struct FixtureDiceKey`.

- [ ] **Step 1: Write the tests**

Create `Packages/SeededCrypto/Tests/SeededCryptoTests/VectorTests.swift`:

```swift
//
//  VectorTests.swift
//  SeededCryptoTests
//
//  Every value in Fixtures/vectors.json was produced by the reference C++ implementation
//  (scripts/generate-vectors.sh). If a `cases` or `legacy` test fails, derived passwords
//  and keys have changed for real users. Do not "fix" the fixture; fix the build.
//

import Foundation
import Testing
@testable import SeededCrypto

struct Vector: Decodable, Sendable, CustomTestStringConvertible {
    var testDescription: String { name }

    let name: String
    let seed: String
    let type: String
    let recipe: String
    let note: String?
    let json: String?
    let error: String?
    let password: String?
    let secretBytesHex: String?
    let keyBytesHex: String?
    let sealingKeyBytesHex: String?
    let unsealingKeyBytesHex: String?
    let signingKeyBytesHex: String?
    let openSshPublicKey: String?
    let sshComment: String?
    let openSshPemPrivateKey: String?
    let pgpUserId: String?
    let pgpTimestamp: UInt32?
    let openPgpPemFormatSecretKey: String?
}

struct FixtureDiceKey: Decodable, Sendable {
    let name: String
    let humanReadableForm: String
    let seed: String
    let seedWithoutOrientations: String
}

struct VectorFixture: Decodable, Sendable {
    let sodiumVersion: String
    let diceKeys: [FixtureDiceKey]
    let cases: [Vector]
    let legacy: [Vector]
    let rejected: [Vector]

    var exampleDiceKeySeed: String { diceKeys[0].seed }
}

let fixture: VectorFixture = {
    let url = Bundle.module.url(forResource: "vectors", withExtension: "json", subdirectory: "Fixtures")!
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(VectorFixture.self, from: Data(contentsOf: url))
}()

@Suite("Derivation vectors from the reference C++")
struct VectorTests {
    @Test("libsodium version matches the vendored source")
    func sodiumVersion() {
        #expect(Recipe.sodiumVersion == fixture.sodiumVersion)
    }

    @Test("the fixture holds the expected sections")
    func sections() {
        #expect(fixture.diceKeys.count == 4)
        #expect(fixture.cases.count > 150)
        #expect(!fixture.legacy.isEmpty)
        #expect(!fixture.rejected.isEmpty)
        #expect(fixture.legacy.allSatisfy { $0.note != nil })
    }

    // `legacy` entries derive on the C++ exactly like `cases`; they are separated only because
    // the Swift port will treat them differently.
    @Test("every case and legacy entry derives to the recorded value", arguments: fixture.cases + fixture.legacy)
    func derives(vector: Vector) throws {
        let json = try #require(vector.json)
        switch vector.type {
        case "Password":
            let password = try Password.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            #expect(password.password == vector.password)
            #expect(password.toJson() == json)
        case "Secret":
            let secret = try Secret.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            #expect(secret.secretBytes().hexString == vector.secretBytesHex)
            #expect(secret.toJson() == json)
        case "SymmetricKey":
            let key = try SymmetricKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            #expect(key.keyBytes.hexString == vector.keyBytesHex)
            #expect(key.toJson() == json)
        case "UnsealingKey":
            let key = try UnsealingKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            #expect(key.unsealingKeyBytes.hexString == vector.unsealingKeyBytesHex)
            #expect(key.sealingKeyBytes.hexString == vector.sealingKeyBytesHex)
            #expect(key.toJson() == json)
        case "SigningKey":
            let key = try SigningKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            #expect(key.signingKeyBytes.hexString == vector.signingKeyBytesHex)
            #expect(key.toJson() == json)
            #expect(key.openSshPublicKey == vector.openSshPublicKey)
            let sshPrivate = try key.openSshPemPrivateKey(comment: vector.sshComment ?? "")
            // The OpenSSH private key block embeds a random check value, so only its shape is stable.
            #expect(sshPrivate.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----"))
            #expect(sshPrivate.count == vector.openSshPemPrivateKey?.count)
            let pgp = try key.openPgpPemFormatSecretKey(userId: vector.pgpUserId ?? "", timestamp: vector.pgpTimestamp ?? 0)
            #expect(pgp == vector.openPgpPemFormatSecretKey)
        default:
            Issue.record("unknown type \(vector.type)")
        }
    }

    @Test("every rejected entry throws", arguments: fixture.rejected)
    func rejects(vector: Vector) {
        #expect(vector.error?.isEmpty == false)
        #expect(throws: SeededCryptoError.self) {
            switch vector.type {
            case "Password": _ = try Password.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            case "Secret": _ = try Secret.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            case "SymmetricKey": _ = try SymmetricKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            case "UnsealingKey": _ = try UnsealingKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            default: _ = try SigningKey.deriveFromSeed(withSeedString: vector.seed, recipe: vector.recipe)
            }
        }
    }

    @Test("the same recipe on the two orientation forms of one key derives different values")
    func orientationsMatter() throws {
        let key = fixture.diceKeys[0]
        let with = try Secret.deriveFromSeed(withSeedString: key.seed, recipe: "")
        let without = try Secret.deriveFromSeed(withSeedString: key.seedWithoutOrientations, recipe: "")
        #expect(with.secretBytes() != without.secretBytes())
    }
}
```

Check `SigningKeys.swift` for the exact names of the two export methods with parameters (`openPgpPemFormatSecretKey(userId:timestamp:)` at line 119 and `openSshPemPrivateKey(comment:)` at line 124 per the current file) and that `timestamp` is `UInt32`; if it is `Int` or `UInt64`, convert `vector.pgpTimestamp` accordingly. Also confirm `SigningKey.signingKeyBytes` and `UnsealingKey.unsealingKeyBytes` are `Data` with `hexString` available (`Native.swift:117`).

Delete `GoldenVectorTests.swift`. In `EmptyRecipeTests.swift` nothing changes if `fixture.exampleDiceKeySeed` is kept as the computed property above; confirm both references (lines 17 and 25) compile.

- [ ] **Step 2: Run the package tests**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd Packages/SeededCrypto && swift test -c release -Xswiftc -enable-testing --parallel 2>&1 | tail -20
```
Expected: all tests pass, including 184 `derives` cases, 12 `rejects` cases, `EmptyRecipeTests` and `ConcurrentFirstUseTests`. The Argon2id legacy cases take a few seconds; that is expected.

- [ ] **Step 3: Lint**

```bash
cd ../.. && swiftlint lint --strict --quiet
```
Expected: no output. (`Packages/SeededCrypto/Tests` is in `.swiftlint.yml`'s `included` list.)

- [ ] **Step 4: Commit**

```bash
git add Packages/SeededCrypto/Tests/SeededCryptoTests/VectorTests.swift
git rm Packages/SeededCrypto/Tests/SeededCryptoTests/GoldenVectorTests.swift
git commit -m "Test every recorded vector, legacy behavior and rejection against the C++"
```

---

### Task 3: The app proves the fixture's seeds

**Files:**
- Modify: `Tests/DiceKeysTests/DiceKeySeedTests.swift`
- Modify: `Tests/DiceKeysTests/PasswordDerivationTests.swift:21`

**Interfaces:**
- Consumes: `DiceKey.createFrom(humanReadableForm:)`, `DiceKey.toSeed(includeOrientations:)`.

- [ ] **Step 1: Write the failing test**

In `Tests/DiceKeysTests/DiceKeySeedTests.swift`, replace the header comment (lines 6-8) with:

```swift
//  The seed string is the only input to every derivation. These expectations were
//  computed independently of the app (see scripts/generate-vectors.cpp and the fixture in
//  Packages/SeededCrypto/Tests/SeededCryptoTests/Fixtures). If they fail, DiceKey
//  canonicalization changed and every derived secret changes with it.
```

and add inside the suite:

```swift
    /// The four DiceKeys in the derivation fixture, as (human-readable form, seed, seed
    /// without orientations). "third" and "fourth" are written in a non-canonical rotation.
    static let fixtureDiceKeys: [(form: String, seed: String, seedWithoutOrientations: String)] = [
        ("A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t",
         "A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t",
         "A1B2C3D4E5F6G1H2I3J4K5L6M1N2O3P4R5S6T1U2V3W4X5Y6Z1"),
        ("F2lY4rC2bV6bX4rK1rD5lS4bG6bZ2lU4rA6tI5bB1lT3rP3lL6lH6lN2tE2rO2rW1tJ5lR1tM2b",
         "F2lY4rC2bV6bX4rK1rD5lS4bG6bZ2lU4rA6tI5bB1lT3rP3lL6lH6lN2tE2rO2rW1tJ5lR1tM2b",
         "F2Y4C2V6X4K1D5S4G6Z2U4A6I5B1T3P3L6H6N2E2O2W1J5R1M2"),
        ("I5lW5tZ5tY2tD3rU1lX3bB4bA2bL2lC1lO1tP1tM2bS1lT1bR3lN2lJ3lE2rF3rG3rV5tH1lK3r",
         "D3tL2bS1bE2tK3tY2lA2rM2rJ3bH1bZ5lB4rP1lN2bV5lW5lX3rO1lR3bG3tI5bU1bC1bT1rF3t",
         "D3L2S1E2K3Y2A2M2J3H1Z5B4P1N2V5W5X3O1R3G3I5U1C1T1F3"),
        ("N1rO6lX2tZ1lY5rA6rR1lE6bD2bM3bB4tP1tC6lU1tI3rK1tL6lW1rH1rJ2lF5lV4lT2rS4bG2l",
         "F5tK1rB4rA6bN1bV4tL6tP1rR1tO6tT2bW1bC6tE6lX2rS4lH1bU1rD2lZ1tG2tJ2tI3bM3lY5b",
         "F5K1B4A6N1V4L6P1R1O6T2W1C6E6X2S4H1U1D2Z1G2J2I3M3Y5"),
    ]

    @Test("the fixture's DiceKeys produce the fixture's seeds", arguments: fixtureDiceKeys)
    func fixtureSeeds(key: (form: String, seed: String, seedWithoutOrientations: String)) throws {
        let diceKey = try DiceKey.createFrom(humanReadableForm: key.form)
        #expect(diceKey.toSeed() == key.seed)
        #expect(diceKey.toSeed(includeOrientations: false) == key.seedWithoutOrientations)
    }
```

In `Tests/DiceKeysTests/PasswordDerivationTests.swift` line 21, change `(see golden-vectors.json)` to `(see the "issue 56 seed" entry in vectors.json)`.

- [ ] **Step 2: Run the test**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate --quiet
UDID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(x["udid"] for r in sorted(d, reverse=True) for x in d[r] if x["isAvailable"] and x["name"].startswith("iPhone")))')
xcodebuild test -project DiceKeys.xcodeproj -scheme DiceKeys -destination "platform=iOS Simulator,id=$UDID" CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= -only-testing:DiceKeysTests/DiceKeySeedTests -only-testing:DiceKeysTests/PasswordDerivationTests 2>&1 | grep -E 'error:|Test Suite|passed|failed'
```
Expected: all pass. This test cannot fail against the app's code and pass against the fixture, or vice versa, since both were produced from the same rotation rules; if it fails, the fixture's seeds are wrong and Task 1's table must be corrected and the fixture regenerated.

- [ ] **Step 3: Commit**

```bash
git add Tests/DiceKeysTests/DiceKeySeedTests.swift Tests/DiceKeysTests/PasswordDerivationTests.swift
git commit -m "Prove the fixture's four DiceKeys against the app's seed canonicalization"
```

---

### Task 4: Docs and the pull request

**Files:**
- Modify: `docs/ARCHITECTURE.md:201-202`, `docs/DEPENDENCIES.md:4`

- [ ] **Step 1: Update the two file names**

In `docs/ARCHITECTURE.md` lines 201-202, change `golden-vectors.json` to `vectors.json`, `scripts/generate-golden-vectors.sh` to `scripts/generate-vectors.sh`, and `GoldenVectorTests` to `VectorTests`. In `docs/DEPENDENCIES.md` line 4, change `scripts/generate-golden-vectors.sh` to `scripts/generate-vectors.sh`. Run `grep -rn "golden" docs README.md Packages/SeededCrypto/Sources Packages/SeededCrypto/Package.swift` and fix any remaining mention the same way.

- [ ] **Step 2: Run everything once more**

Package tests (Task 2 Step 2), app tests for the two suites (Task 3 Step 2), `swiftlint lint --strict --quiet`, `shellcheck scripts/*.sh`. Expected: green and silent.

- [ ] **Step 3: Commit and push**

```bash
git add docs
git commit -m "Point the docs at the vector generator"
git push -u origin derivation-vectors
```

- [ ] **Step 4: Open the PR**

Title: `Record every derivation vector the Swift port must reproduce`

Body:

```
The vendored C++ is the only reference implementation of DiceKeys derivation, and the plan is to delete it. Twelve golden vectors are not enough to prove a replacement: nothing covered a second DiceKey, a seed without orientations, any length bound, whitespace or key order in the recipe, the 1024 word list, or the inputs the C++ accepts by accident.

## Decisions

- Three sections. `cases` is the compatibility contract; `legacy` records what the C++ produces for inputs the port will reject or change (Argon2id, lenient numbers, lengths past the HKDF limit, the inverted bits-versus-words check), so those behaviors can be restored and verified later; `rejected` records the C++'s refusals.
- Four DiceKeys, two of them written in a non-canonical rotation, each with and without orientations. The app's seed tests prove the fixture's seeds are what `toSeed()` computes.
- Seal, unseal, sign and verify outputs are no longer recorded; the port drops those operations.

Verified: 165 cases, 19 legacy and 12 rejected entries derive or fail on the vendored C++ exactly as recorded; the three values that existed in the old fixture are unchanged.
```
