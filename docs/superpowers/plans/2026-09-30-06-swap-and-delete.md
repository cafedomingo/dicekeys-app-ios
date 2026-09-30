# Swap and Delete Implementation Plan (PR 6 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app derives through the Swift engine; the vendored libsodium, seeded-crypto, the C shim, the old wrapper, their scripts and every comparison test are gone; the durable documentation replaces the spec and plans.

**Architecture:** `SwiftEngine` becomes `Engine`, the only implementation, called directly by the derived types; the engine protocol, `LegacyEngine` and `DerivationError.engineRejected` disappear. `Packages/SeededCrypto` is deleted with its scripts and CI job; lint and project config stop mentioning it. `docs/derivation.md`, `docs/recipe-format.md` and `docs/recipe-schema.json` are written from the spec, `docs/DEPENDENCIES.md` is deleted, `ARCHITECTURE.md`, the README and `THIRD_PARTY_LICENSES` are corrected, and `docs/superpowers/` is removed.

**Tech Stack:** Swift 6.2, Swift Testing, XcodeGen, SwiftLint, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-29-derivation-rewrite-design.md`, "PR sequence" item 6 and "Docs"; it is deleted by this plan's last task, so Task 2 harvests it first.

## Global Constraints

- Every `cases` fixture entry must still derive to its recorded value through the public API, now via the Swift engine; every `legacy` entry must be refused by `Recipe`; every `rejected` entry except "consistent lengthInBits and lengthInWords" must be refused by `Recipe`, and that one must derive.
- Package tests: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; swift test --package-path Packages/Derivation -c release -Xswiftc -enable-testing --parallel`. App: `xcodegen generate --quiet` then the full `DiceKeysTests` run and the unused-code analyze check (commands in plan 03's Global Constraints). `swiftlint lint --strict --quiet`, `actionlint`, `shellcheck scripts/*.sh`, `ruff check scripts` and `ruff format --check scripts` all silent.
- American spelling; no em-dashes; comments explain why, never what changed or what was deleted; no attribution trailers; docs lean (only what code and config cannot tell).
- `docs/BACKLOG.md` is not touched here: PR #17 rewrites it on main, and the stack predates that. Closing the "Derive in Swift" item is a one-line follow-up after #17 and this stack have merged.
- Branch `derivation-swap`, stacked on `derivation-swift-engine` (PR #22); the PR's base is `derivation-swift-engine`.

## Review Focus

1. After the swap, `DiceKey.idBytes` for the example key must still be `31f6979a628e4800780118a5dc466129` (`DiceKeySeedTests.diceKeyId`), or every saved DiceKey is lost. Task 1.
2. The app's derive screen must show the Swift engine's errors (`DerivationError.errorDescription`) for a rejected stored recipe exactly as before; nothing in the app changes. Task 1 (existing `RecipeBuildingTests.rejectedRecipeReports`).
3. No file anywhere in the repository may still reference `SeededCrypto`, `CSodium`, `libsodium`, `seeded-crypto`, `LegacyEngine` or `engineRejected` except `THIRD_PARTY_LICENSES` (the seeded-crypto attribution stays) and `docs/derivation.md` (which says what the port came from). Task 3 greps for it.
4. The fixture can never be regenerated once the generator is gone; the docs must say so, and `VectorTests` must still pin the counts. Task 2.
5. The word lists' digests and the KAT fixture's provenance survive; `WordLists.swift`'s header must not claim a generator that no longer exists. Task 1.

---

## File Structure

```
Packages/Derivation/Sources/Derivation/Engine.swift          renamed from SwiftEngine.swift
Packages/Derivation/Sources/Derivation/DerivationEngine.swift   deleted
Packages/Derivation/Sources/Derivation/LegacyEngine.swift       deleted
Packages/Derivation/Sources/Derivation/DerivationError.swift    engineRejected removed
Packages/Derivation/Sources/Derivation/Derived.swift            calls Engine()
Packages/Derivation/Sources/Derivation/WordLists.swift          header reworded
Packages/Derivation/Package.swift                               no SeededCrypto dependency
Packages/Derivation/Tests/DerivationTests/VectorTests.swift     legacy and rejected tests rewritten
Packages/Derivation/Tests/DerivationTests/RecipeTests.swift     engineRejected removed from the messages list
Packages/Derivation/Tests/DerivationTests/EngineComparisonTests.swift   deleted
Packages/Derivation/Tests/DerivationTests/HKDFTests.swift               deleted
Packages/Derivation/Tests/DerivationTests/SchemaTests.swift             new
Packages/Derivation/Tests/BLAKE2Tests/LibsodiumCrossCheckTests.swift    deleted
Packages/SeededCrypto/                                          deleted
scripts/generate-vectors.sh, generate-vectors.cpp, vendor-libsodium.sh, update-seeded-crypto.sh, generate-word-lists.py   deleted
.swiftlint.yml, .github/workflows/build.yml, project.yml        SeededCrypto lines removed
docs/derivation.md, docs/recipe-format.md, docs/recipe-schema.json   new
docs/DEPENDENCIES.md                                            deleted
docs/ARCHITECTURE.md, README.md, THIRD_PARTY_LICENSES            corrected
docs/superpowers/                                               deleted
```

---

### Task 1: Swap the engine and delete the C++

**Files:** as listed above under `Packages/`, `scripts/`, `.swiftlint.yml`, `.github/workflows/build.yml`, `project.yml`.

- [ ] **Step 1: Rewrite the tests that named the legacy engine**

`VectorTests.swift`:
- Remove `import SeededCrypto`, the `sodiumVersion` property from `VectorFixture` and the `sodiumVersion` test.
- `legacy(vector:)` keeps only `#expect(throws: DerivationError.self) { try Recipe(json: vector.recipe, type: type) }`; update its comment: the strict parser refuses every legacy recipe; the fixture records what the C++ produced for them so the behavior could be restored.
- `rejects(vector:)`: every entry except the one named "consistent lengthInBits and lengthInWords" is refused by `Recipe`; for that one, assert `try Recipe(json: vector.recipe, type: type).lengthInWords == 10` and that `Password.derive(seed: vector.seed, recipe: vector.recipe).password.hasPrefix("10-")`.
- `consistentBitsAndWords()`: assert `Password.derive` succeeds with a password starting `10-`; comment: the C++ rejected this correct pair, the port derives it.

`RecipeTests.messages`: remove `.engineRejected("x")` from the list.

Delete `EngineComparisonTests.swift`, `HKDFTests.swift` (its `SplitMix64` is used only there: confirm with grep; if `PasswordFormatterTests` or another file uses it, move the struct there) and `Tests/BLAKE2Tests/LibsodiumCrossCheckTests.swift`.

- [ ] **Step 2: Swap and simplify the seam**

- `git mv Packages/Derivation/Sources/Derivation/SwiftEngine.swift Packages/Derivation/Sources/Derivation/Engine.swift`; rename `struct SwiftEngine: DerivationEngine` to `struct Engine: Sendable`; the doc comment becomes: "The derivation: HKDF over BLAKE2b for the bytes, CryptoKit for the curves, and the reference JSON layout for the result. Every `derive` on the derived types comes here."
- Delete `DerivationEngine.swift` and `LegacyEngine.swift`.
- `Derived.swift`: replace each `try defaultEngine.derive(` with `try Engine().derive(`; the header comment's "the JSON its engine produced" becomes "the JSON the engine produced".
- `DerivationError.swift`: delete the `engineRejected` case, its doc comment and its `errorDescription` arm.
- `WordLists.swift` header: "The word lists seeded-crypto shipped, copied verbatim. A word is chosen by index, so the order is part of every password ever derived; `PasswordFormatterTests` pins each list by digest."
- `Package.swift`: remove `dependencies: [.package(path: "../SeededCrypto")]`, the `.product(name: "SeededCrypto", ...)` entries from `Derivation` and `DerivationTests`, and the `CSodium` product dependency from `BLAKE2Tests`; update the header comment (the engine is in Swift; no mention of the C++).

Run: package tests (all green), `swiftlint lint --strict --quiet`.

Commit: `git add -A Packages/Derivation && git commit -m "Derive in Swift"`

- [ ] **Step 3: Delete the C++ and everything that existed for it**

```bash
git rm -r -q Packages/SeededCrypto
git rm -q scripts/generate-vectors.sh scripts/generate-vectors.cpp scripts/vendor-libsodium.sh scripts/update-seeded-crypto.sh scripts/generate-word-lists.py
```
`.swiftlint.yml`: remove the four `Packages/SeededCrypto/...` lines under `included` and `excluded` (delete the `excluded:` key if nothing is left under it). `.github/workflows/build.yml`: in the `crypto` job delete the "Build and test" step for `Packages/SeededCrypto` and reword the job comment to describe the Derivation package's tests (the vectors, BLAKE2b's known answers); check whether `scripts/requirements.txt` (Pillow, for the icon generator) is still needed; leave it. `project.yml` header comment: two local packages, `Derivation` and `ReadDiceKey`.

Run: `actionlint`, `shellcheck scripts/*.sh`, `ruff check scripts && ruff format --check scripts`, `swiftlint lint --strict --quiet`, `xcodegen generate --quiet`, the full app test run, and the analyze check. All green and silent. Then `grep -rn "SeededCrypto\|CSodium\|LegacyEngine\|engineRejected\|sodiumVersion\|generate-vectors\|vendor-libsodium\|update-seeded-crypto\|generate-word-lists" --exclude-dir=.git --exclude-dir=.build --exclude-dir=.superpowers --exclude-dir=.claude .` must return only hits under `docs/` (handled in Tasks 2 and 3) and `THIRD_PARTY_LICENSES`.

Commit: `git add -A && git commit -m "Delete the vendored libsodium and seeded-crypto and their scripts"` (check `git status` first: nothing under `.build`, no `.xcodeproj`, no logs).

---

### Task 2: The durable docs

**Files:**
- Create: `docs/derivation.md`, `docs/recipe-format.md`, `docs/recipe-schema.json`, `Packages/Derivation/Tests/DerivationTests/SchemaTests.swift`
- Delete: `docs/DEPENDENCIES.md`
- Modify: `docs/ARCHITECTURE.md`, `README.md`, `THIRD_PARTY_LICENSES`

Write from the spec (`docs/superpowers/specs/2026-09-29-derivation-rewrite-design.md`, still present in this task) and from the code. Lean: each document says only what the code and config cannot.

- [ ] **Step 1: `docs/recipe-format.md`**

Sections: what a recipe is (the empty string or a JSON object; the text is hashed exactly as given, so whitespace, key order and unknown fields change the result); the field table from the spec (`type`, `algorithm`, `hashFunction`, `lengthInBytes`, `lengthInChars`, `lengthInBits`, `lengthInWords`, `wordList`, with types, defaults and allowed values); the salt-only fields the format defines but this app never reads (`purpose` and `#` are read by the app for naming and defaults, the rest listed); the validation rules (integers must be integers, the bounds, the bits/words resolution, unknown names fail); the canonical form the app writes for hand-built and raw recipes (from `RecipeJson.swift`: no whitespace, `purpose` first, `#` last, UTF-16 code unit order, keys decoded, duplicates rejected, 128 levels); the two word lists by name with their sizes. One paragraph on why unknown names fail rather than fall back. No history.

- [ ] **Step 2: `docs/derivation.md`**

Sections: the construction (info = type string + recipe text; HKDF over keyed BLAKE2b exactly as in `HKDF.swift`, with the 8160-byte limit); per type (password words and formatting, secret, symmetric key, X25519 via SHA-512 of the derived bytes, Ed25519 via the derived bytes as seed, `signingKeyBytes` = seed || public key); the JSON output layouts table from the spec; key formats (OpenSSH layout and the derived check value; OpenPGP packets, timestamp 0 and why, the randomized self-signature and what stays fixed); the seed string (75 characters, canonical rotation; the DiceKey id recipe); the compatibility contract as a numbered list (from the spec's "Compatibility contract"); the legacy behaviors table from the spec's "Legacy behaviors" (what the C++ did, what this does), with a sentence that the `legacy` section of `vectors.json` records the C++ output for each so the behavior could be restored and verified; the fixture's provenance and the fact that it cannot be regenerated (the generator and the C++ are gone; the fixture is the reference); the memory statement from the spec's "Docs" section (no zeroing or locking; short lifetimes; nothing logged; pasteboard local-only with a one-minute expiry); a short "adding a hash function or word list" paragraph (one enum case, one implementation, one fixture case generated by the Swift engine, and the name becomes part of the format). Where it came from: one sentence naming dicekeys/seeded-crypto as the origin of the construction, the word lists and the layouts.

- [ ] **Step 3: `docs/recipe-schema.json` and its test**

A JSON Schema (draft 2020-12) describing the object `Recipe` reads: `type` (enum of the five), `algorithm` (enum of the three), `hashFunction` (enum `["BLAKE2b"]`), `lengthInBytes`, `lengthInChars`, `lengthInBits`, `lengthInWords` (integers with the minimums; `lengthInBytes` maximum 8160, `lengthInWords` maximum 1020), `wordList` (enum of the two names), `purpose` (string), `#` (integer minimum 1), `additionalProperties: true` with a `description` saying unknown fields are salt. `SchemaTests.swift` decodes the file with `JSONSerialization`, asserts the eight field names `Recipe` reads are all present under `properties` with the expected `enum`/`minimum`/`maximum` values, and asserts every `cases` fixture recipe that is a non-empty object has no property that the schema types differently (a small hand-written check: for each property in the schema with an `enum`, every fixture value under that name is a member; for each with `minimum`/`maximum`, every fixture value is an integer in range). Load the schema through `Bundle.module` by adding `docs/recipe-schema.json` to the test target's resources with `.copy("../../../../docs/recipe-schema.json")` if SwiftPM allows a path outside the target; if it does not, keep a copy at `Tests/DerivationTests/Fixtures/recipe-schema.json` and have the test assert it is byte-identical to `docs/recipe-schema.json` read from the repository path derived from `#filePath`.

- [ ] **Step 4: Correct the existing docs**

- `docs/ARCHITECTURE.md`: companion documents list drops `DEPENDENCIES.md` and adds `derivation.md` and `recipe-format.md`; "The app in one paragraph" names two packages (`Derivation` with its three targets, `ReadDiceKey`) and drops the two Derivation sentences that describe the transition; goal 1 says the derivation is Swift, guarded by vectors recorded from the reference implementation; "What CI covers" lists the Derivation package's suites; "How the safety nets work" drops the re-vendoring bullet and says the fixture cannot be regenerated; the "C++ in Swift or Rust: the decision" section is rewritten in the past tense as one short paragraph: the C++ was ported to Swift over a BLAKE2b written here, proven by 168 recorded vectors, the official BLAKE2b known answers and, while it existed, byte-for-byte comparison with the C++; the licensing paragraph drops libsodium and nlohmann.
- `README.md`: lines 22-24 become one sentence (the derivation and the scanner are pure Swift in two local packages; see `docs/ARCHITECTURE.md`); line 48's list drops lib-seeded, libsodium and nlohmann and adds the BLAKE2 test vectors (CC0).
- `THIRD_PARTY_LICENSES`: item 3 (seeded-crypto) becomes an attribution for a port: Origin unchanged, "Where: the derivation construction, JSON layouts, key formats and word lists in Packages/Derivation are ported from lib-seeded; no seeded-crypto source remains", MIT text kept; delete items 4, 5 and 6 (nlohmann, SHA1, libsodium) and renumber; item 1's "Where" paths drop `DiceKeys/Model/BIP39` and `DiceKeys/Services/Api` (neither exists); the BIP-39 item's "Where" becomes `Packages/Derivation/Sources/KeyFormats/Wordlist.swift`.
- `git rm docs/DEPENDENCIES.md`.

Run: package tests (the schema test), `swiftlint lint --strict --quiet`.

Commit: `git add -A docs README.md THIRD_PARTY_LICENSES Packages/Derivation && git commit -m "Document the derivation and the recipe format"`

---

### Task 3: Remove the spec and plans, verify, open the PR

- [ ] **Step 1: Delete the temporary documents**

`git rm -r -q docs/superpowers`. Then the grep from Task 1 Step 3 must return only `THIRD_PARTY_LICENSES` (seeded-crypto attribution) and `docs/derivation.md`.

- [ ] **Step 2: Verify everything**

Package tests, `swiftlint lint --strict --quiet`, `actionlint`, `shellcheck scripts/*.sh`, `ruff check scripts`, `ruff format --check scripts`, `xcodegen generate --quiet`, the full app test run, the analyze check, and `xcodebuild build-for-testing` of the `DiceKeysScreenWalk` scheme (the UI test target must still compile).

- [ ] **Step 3: Commit and push**

```bash
git commit -m "Remove the rewrite's design spec and plans now that they have landed"
git push -u origin derivation-swap
```

- [ ] **Step 4: Open the PR** (base `derivation-swift-engine`)

Title: `Derive in Swift and delete the vendored C++`

Body:
```
The app now derives every password, secret and key through the Swift engine, and libsodium, seeded-crypto, the C shim and the old wrapper are gone: about 79,000 lines of vendored C and C++ replaced by under 2,000 lines of Swift, half of them word lists.

## Decisions

- The engine seam is gone with the C++: there is one engine, called directly.
- The comparison tests that needed the C++ are deleted; everything they proved is also pinned by tests that read only the recorded fixture, which stays and can no longer be regenerated. docs/derivation.md says so.
- docs/derivation.md and docs/recipe-format.md replace the vendored doxygen and the design spec; docs/recipe-schema.json is the format in machine form, kept honest by a test. docs/DEPENDENCIES.md is gone: nothing unusual is vendored any more.
- THIRD_PARTY_LICENSES keeps the seeded-crypto attribution as the origin of the port and drops libsodium, nlohmann and the bundled SHA1.
- The backlog's "Derive in Swift" item is closed in a follow-up after PR #17 lands, since that PR rewrites the file.

Verified: 168 vector cases through the Swift engine, 21 legacy refusals, 15 rejections plus the one correct pair the C++ refused now deriving, the DiceKey id vector, the app's suites, and the screen walk build.
```
