# Derivation Package Implementation Plan (PR 3 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put the app behind the `Derivation` package's public API (strict recipe parsing, the five derived types, `KeyFormats`) with the vendored C++ still doing the derivation behind an engine seam, so the Swift engine can later be swapped in without the app noticing.

**Architecture:** A new local package `Packages/Derivation` with two products. `Derivation` holds the recipe JSON parser (moved from the app), the strict `Recipe` validator, the derived value types, and an internal `DerivationEngine` protocol whose only implementation for now is `LegacyEngine` over `SeededCrypto`. `KeyFormats` holds BIP39 (moved from the app) and OpenSSH/OpenPGP exports that forward to `SeededCrypto` until PR 5 replaces their bodies. The vector fixture and its tests move into the package. The app imports `Derivation` and `KeyFormats` and no longer imports `SeededCrypto`.

**Tech Stack:** Swift 6.2 packages (typed throws, strict concurrency), Swift Testing, XcodeGen, xcodebuild, SwiftLint.

**Spec:** `docs/superpowers/specs/2026-09-29-derivation-rewrite-design.md`, sections "Public API", "Recipe format", "Derivation" (the `toJson()` table), "App changes" and "PR sequence" item 3. The spec lives on this branch.

## Global Constraints

- iOS 26 / macOS 26, tools 6.2, strict concurrency. No external package dependencies.
- **No derived output changes.** Every `cases` entry in `Packages/Derivation/Tests/DerivationTests/Fixtures/vectors.json` (after Task 3 moves it) must derive to the recorded values through the public API; every `legacy` entry must still derive to its recorded value through `LegacyEngine`.
- Package tests as CI runs them: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; cd Packages/Derivation && swift test -c release -Xswiftc -enable-testing --parallel` (and the same in `Packages/SeededCrypto`).
- App build and tests as in plan 01: `xcodegen generate --quiet`, then `xcodebuild test -project DiceKeys.xcodeproj -scheme DiceKeys -destination "platform=iOS Simulator,id=$UDID" CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=`; the unused-code check `xcodebuild build ... CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= > build-ios.log 2>&1; swiftlint analyze --strict --config .swiftlint.yml --config .swiftlint-analyze.yml --compiler-log-path build-ios.log`.
- `swiftlint lint --strict --quiet` prints nothing. SwiftLint rejects trailing commas in collection literals; test literals containing `"#` need `##"..."##`.
- American spelling; no em-dashes; comments explain why, never what changed or what was deleted; no attribution trailers; no test-only accessors or lint suppressions in product code (the existing `force_try` suppressions on fixture loading and the DiceKey id are the accepted exceptions).
- Branch `derivation-package`, stacked on `derivation-vectors` (PR #19) in worktree `.claude/worktrees/derivation-rewrite`. The PR's base is `derivation-vectors`.

## Review Focus

1. A stored recipe that the C++ accepted but the strict parser rejects (for example `{"lengthInBytes":16.9}`) must show the parser's message on the derive screen, not crash and not silently derive. Task 5.
2. The public `derive` for a `cases` recipe with `"type"` or `"algorithm"` present must succeed; a `"type"` naming another kind must fail with `typeMismatch` before anything is derived. Task 2 and Task 3.
3. `DiceKey.idBytes` must produce `31f6979a628e4800780118a5dc466129` for the example key after the switch, or every saved DiceKey stops being found. Task 5 (existing `DiceKeySeedTests.diceKeyId`).
4. A stored `DerivationRecipe` JSON written by earlier versions (`"type":"Password"` etc.) must decode after the type rename. Task 5.
5. The derive screen with no DiceKey loaded must render no value instead of deriving from the example key. Task 5.

---

## File Structure

```
Packages/Derivation/
  Package.swift
  Sources/Derivation/
    RecipeJson.swift          moved from DiceKeys/Model/Recipes, made public
    DerivableType.swift       the five kinds
    DerivationError.swift     every failure, with messages
    HashFunction.swift        enum, BLAKE2b only
    WordList.swift            the two list names and their bits per word
    Recipe.swift              strict parsing and validation
    DerivationEngine.swift    the seam: protocol + defaultEngine
    LegacyEngine.swift        over SeededCrypto
    Derived.swift             Password, Secret, SymmetricKey, UnsealingKey, SigningKey
    Hex.swift                 Data(hex:) for decoding engine JSON
  Sources/KeyFormats/
    OpenSSH.swift             forwards to SeededCrypto until PR 5
    OpenPGP.swift             forwards to SeededCrypto until PR 5
    BIP39.swift               public entry point
    Mnemonic.swift            moved from DiceKeys/Model/BIP39
    Wordlist.swift            moved from DiceKeys/Model/BIP39
  Tests/DerivationTests/
    Fixtures/vectors.json     moved from SeededCrypto
    RecipeJsonTests.swift     moved from Tests/DiceKeysTests
    RecipeTests.swift         validation rules
    VectorTests.swift         moved and rewritten over the public API and LegacyEngine
    KeyFormatsTests.swift     BIP39 vectors (moved) and export vectors
```

App: `DerivationRecipe.swift`, `DerivedValue.swift`, `DiceKey.swift`, `CustomRecipeModel.swift`, `CustomRecipeForm.swift`, `DerivedValueScreen.swift`, `RecipeListView.swift`, `DerivationRecipeTemplates.swift`, `SeededCryptoRecipeType.swift` (replaced by `DerivableType+Descriptions.swift`), `project.yml`, `.swiftlint.yml`, `.github/workflows/build.yml`, `.github/dependabot.yml`, `scripts/generate-vectors.sh`, docs.

---

### Task 1: The package skeleton, with the recipe JSON parser moved into it

**Files:**
- Create: `Packages/Derivation/Package.swift`
- Move: `DiceKeys/Model/Recipes/RecipeJson.swift` → `Packages/Derivation/Sources/Derivation/RecipeJson.swift`
- Move: `Tests/DiceKeysTests/RecipeJsonTests.swift` → `Packages/Derivation/Tests/DerivationTests/RecipeJsonTests.swift`
- Create: `Packages/Derivation/Sources/KeyFormats/KeyFormats.swift` (placeholder so the target exists; Task 4 replaces it)
- Modify: `DiceKeys/Model/Recipes/DerivationRecipe.swift:8-9` (imports), `DiceKeys/Features/Recipes/CustomRecipeModel.swift:8-9` (imports)
- Modify: `project.yml` (packages and dependencies), `.swiftlint.yml` (`included`), `.github/workflows/build.yml` (crypto job), `.github/dependabot.yml`

**Interfaces:**
- Produces: package `Derivation` with products `Derivation` and `KeyFormats`; `public` on `RecipeJsonValue`, `RecipeJsonField`, `RecipeJsonError`, `RecipeJsonParser`, `quotedJsonString`, `String.canonicalizedRecipe()`; `RecipeJsonError.duplicateKey(name: String, offset: Int)` (the name is added so Task 2 can report which field).

- [ ] **Step 1: Create the manifest**

`Packages/Derivation/Package.swift`:

```swift
// swift-tools-version: 6.2
//
// Derivation: recipes and the passwords, secrets and keys derived from a DiceKey seed.
//
//   Derivation   recipe parsing and validation, the derived value types, and the engine
//                that does the hashing (the vendored C++ in SeededCrypto for now)
//   KeyFormats   OpenSSH, OpenPGP and BIP39 encodings of derived values

import PackageDescription

let package = Package(
    name: "Derivation",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "Derivation", targets: ["Derivation"]),
        .library(name: "KeyFormats", targets: ["KeyFormats"]),
    ],
    dependencies: [
        .package(path: "../SeededCrypto"),
    ],
    targets: [
        .target(
            name: "Derivation",
            dependencies: [.product(name: "SeededCrypto", package: "SeededCrypto")]
        ),
        .target(
            name: "KeyFormats",
            dependencies: ["Derivation", .product(name: "SeededCrypto", package: "SeededCrypto")]
        ),
        .testTarget(
            name: "DerivationTests",
            dependencies: ["Derivation", "KeyFormats"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

Create `Packages/Derivation/Sources/KeyFormats/KeyFormats.swift` containing only `import Derivation` and a doc comment `// Encodings of derived values. Filled in by the key formats task.` so the target compiles; Task 4 replaces the file. Create the directory `Packages/Derivation/Tests/DerivationTests/Fixtures` with a placeholder file `README.md` containing one line, `Vectors generated by scripts/generate-vectors.sh.`, so the resource directory exists before Task 3 moves the fixture in (SwiftPM refuses a missing resource path).

- [ ] **Step 2: Move the parser and make it public**

`git mv DiceKeys/Model/Recipes/RecipeJson.swift Packages/Derivation/Sources/Derivation/RecipeJson.swift`. Then in that file:
- add `public` to: `indirect enum RecipeJsonValue`, its two static helpers `text(_:)` and `int(_:)`, `var canonicalText`; `struct RecipeJsonField` and its `init(name:value:)` and stored properties; `static func precedes`; `enum RecipeJsonError` and `var message`; `struct RecipeJsonParser` and its two static functions `parseObject(_:)` and `decodeString(quoted:)`; `func quotedJsonString(_:)`; and the `String.canonicalizedRecipe()` extension method.
- change `case duplicateKey(offset: Int)` to `case duplicateKey(name: String, offset: Int)`; at the throw site pass the decoded name; the `message` text stays `Each field name may appear only once`.
- update the header comment's first line to name the package: `//  RecipeJson.swift` / `//  Derivation`.

`git mv Tests/DiceKeysTests/RecipeJsonTests.swift Packages/Derivation/Tests/DerivationTests/RecipeJsonTests.swift`; change `@testable import DiceKeys` to `import Derivation`; any test that matched `.duplicateKey(offset:)` by pattern must match the new shape (`case .duplicateKey = thrown` patterns keep working; an exact `#expect(throws: RecipeJsonError.duplicateKey(offset: N))` needs `name:` added; grep for `duplicateKey` in the test file).

- [ ] **Step 3: Wire the app to the package**

`project.yml`: under `packages:` add
```yaml
  Derivation:
    path: Packages/Derivation
```
and in both `DiceKeys` and `DiceKeysTests` `dependencies:` add
```yaml
      - package: Derivation
        product: Derivation
      - package: Derivation
        product: KeyFormats
```
Keep the `SeededCrypto` dependency for now; Task 5 removes it. Update the header comment of `project.yml` (line 6-7) to: `# Native dependencies come from three local Swift packages: Packages/Derivation (recipes and derived values, over Packages/SeededCrypto, which compiles libsodium and seeded-crypto from vendored sources) and Packages/ReadDiceKey (the scanner, in Swift).`

`DiceKeys/Model/Recipes/DerivationRecipe.swift`: add `import Derivation` after `import SeededCrypto`. `DiceKeys/Features/Recipes/CustomRecipeModel.swift`: add `import Derivation` after `import Observation`.

`.swiftlint.yml` `included:` add `Packages/Derivation/Sources` and `Packages/Derivation/Tests`.

`.github/workflows/build.yml`, in the `crypto` job (the one with `working-directory: Packages/SeededCrypto`; read lines 68-90 to find it), add a second step after "Build and test package":
```yaml
      - name: Build and test Derivation
        working-directory: Packages/Derivation
        run: swift test -c release -Xswiftc -enable-testing --parallel
```
Update the job's comment (line 70) to mention both packages.

`.github/dependabot.yml`: after the `/BuildTools` swift entry add
```yaml
  - package-ecosystem: "swift"
    directory: "/Packages/Derivation"
    schedule:
      interval: "weekly"
    labels: ["dependencies"]
```

- [ ] **Step 4: Build and test everything**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
(cd Packages/Derivation && swift test -c release -Xswiftc -enable-testing --parallel 2>&1 | tail -5)
xcodegen generate --quiet
UDID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(x["udid"] for r in sorted(d, reverse=True) for x in d[r] if x["isAvailable"] and x["name"].startswith("iPhone")))')
xcodebuild test -project DiceKeys.xcodeproj -scheme DiceKeys -destination "platform=iOS Simulator,id=$UDID" CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= 2>&1 | grep -E 'error:|Test Suite|passed|failed|\*\*'
swiftlint lint --strict --quiet
actionlint
```
Expected: the package's `RecipeJsonTests` pass (the same count as before the move); the app builds and all `DiceKeysTests` pass (one suite fewer); lint and actionlint silent. `actionlint` is in `scripts/requirements-lint.txt`; if it is not installed, `pip3 install -r scripts/requirements-lint.txt`.

- [ ] **Step 5: Commit**

```bash
git add -A Packages/Derivation DiceKeys/Model/Recipes Tests/DiceKeysTests DiceKeys/Features/Recipes/CustomRecipeModel.swift project.yml .swiftlint.yml .github
git commit -m "Start the Derivation package with the recipe JSON parser"
```

---

### Task 2: Strict recipe parsing

**Files:**
- Create: `Packages/Derivation/Sources/Derivation/DerivableType.swift`, `DerivationError.swift`, `HashFunction.swift`, `WordList.swift`, `Recipe.swift`
- Test: `Packages/Derivation/Tests/DerivationTests/RecipeTests.swift`

**Interfaces:**
- Consumes: `RecipeJsonParser.parseObject`, `RecipeJsonParser.decodeString`, `RecipeJsonError`.
- Produces:
```swift
public enum DerivableType: String, Codable, CaseIterable, Identifiable, Sendable {
    case password = "Password", secret = "Secret", signingKey = "SigningKey",
         symmetricKey = "SymmetricKey", unsealingKey = "UnsealingKey"
}
public enum HashFunction: String, Sendable { case blake2b = "BLAKE2b" }
public enum WordList: String, CaseIterable, Sendable { case en512 = "EN_512_words_5_chars_max_ed_4_20200917"; case en1024 = "EN_1024_words_6_chars_max_ed_4_20200917"; public var bitsPerWord: Int; public var count: Int }
public struct Recipe: Sendable, Equatable { json, type, hashFunction, lengthInBytes, lengthInChars, wordList, lengthInWords; init(json:type:) throws(DerivationError) }
public enum DerivationError: Error, Equatable, Sendable, LocalizedError { ... }
```

- [ ] **Step 1: Write the failing tests**

`Packages/Derivation/Tests/DerivationTests/RecipeTests.swift`:

```swift
//
//  RecipeTests.swift
//  DerivationTests
//

import Testing
import Derivation

@Suite("Recipe parsing and validation")
struct RecipeTests {
    @Test("the empty recipe and the empty object take every default")
    func defaults() throws {
        for json in ["", "{}"] {
            let secret = try Recipe(json: json, type: .secret)
            #expect(secret.lengthInBytes == 32)
            #expect(secret.hashFunction == .blake2b)
            let password = try Recipe(json: json, type: .password)
            #expect(password.lengthInWords == 15)
            #expect(password.lengthInBytes == 120)
            #expect(password.lengthInChars == nil)
            #expect(password.wordList == .en512)
            for type in [DerivableType.symmetricKey, .unsealingKey, .signingKey] {
                #expect(try Recipe(json: json, type: type).lengthInBytes == 32)
            }
        }
    }

    @Test("the raw text is kept exactly")
    func keepsText() throws {
        let text = " {\"purpose\" : \"x\" }\n"
        #expect(try Recipe(json: text, type: .secret).json == text)
    }

    @Test("unknown fields are ignored")
    func unknownFields() throws {
        let recipe = try Recipe(json: #"{"purpose":"x","#":2,"allow":[{"host":"*.example.com"}],"excludeOrientationOfFaces":true,"clientMayRetrieveKey":true,"hashFunctionMemoryLimitInBytes":8192,"zzz":[1,{"a":null}]}"#, type: .secret)
        #expect(recipe.lengthInBytes == 32)
    }

    @Test("a declared type must match the requested one")
    func typeField() throws {
        #expect(try Recipe(json: #"{"type":"Password"}"#, type: .password).type == .password)
        #expect(throws: DerivationError.typeMismatch(recipe: "Secret", requested: .password)) {
            try Recipe(json: #"{"type":"Secret"}"#, type: .password)
        }
        #expect(throws: DerivationError.typeMismatch(recipe: "bogus", requested: .secret)) {
            try Recipe(json: #"{"type":"bogus"}"#, type: .secret)
        }
        #expect(throws: DerivationError.wrongType(field: "type", expected: "a string")) {
            try Recipe(json: #"{"type":1}"#, type: .secret)
        }
    }

    @Test("each key type accepts only its own algorithm, and secrets and passwords accept none")
    func algorithmField() throws {
        #expect(try Recipe(json: #"{"algorithm":"XSalsa20Poly1305"}"#, type: .symmetricKey).lengthInBytes == 32)
        #expect(try Recipe(json: #"{"algorithm":"X25519"}"#, type: .unsealingKey).lengthInBytes == 32)
        #expect(try Recipe(json: #"{"algorithm":"Ed25519"}"#, type: .signingKey).lengthInBytes == 32)
        #expect(throws: DerivationError.invalidAlgorithm("X25519")) { try Recipe(json: #"{"algorithm":"X25519"}"#, type: .symmetricKey) }
        #expect(throws: DerivationError.invalidAlgorithm("Ed25519")) { try Recipe(json: #"{"algorithm":"Ed25519"}"#, type: .unsealingKey) }
        #expect(throws: DerivationError.invalidAlgorithm("X25519")) { try Recipe(json: #"{"algorithm":"X25519"}"#, type: .signingKey) }
        #expect(throws: DerivationError.invalidAlgorithm("X25519")) { try Recipe(json: #"{"algorithm":"X25519"}"#, type: .secret) }
        #expect(throws: DerivationError.invalidAlgorithm("bogus")) { try Recipe(json: #"{"algorithm":"bogus"}"#, type: .password) }
    }

    @Test("only BLAKE2b is a known hash function")
    func hashFunctionField() throws {
        #expect(try Recipe(json: #"{"hashFunction":"BLAKE2b"}"#, type: .secret).hashFunction == .blake2b)
        #expect(throws: DerivationError.unsupportedHashFunction("Argon2id")) { try Recipe(json: #"{"hashFunction":"Argon2id"}"#, type: .secret) }
        #expect(throws: DerivationError.unsupportedHashFunction("SHA256")) { try Recipe(json: #"{"hashFunction":"SHA256"}"#, type: .secret) }
    }

    @Test("secret length is 1 to 8160 bytes")
    func secretLength() throws {
        #expect(try Recipe(json: #"{"lengthInBytes":1}"#, type: .secret).lengthInBytes == 1)
        #expect(try Recipe(json: #"{"lengthInBytes":8160}"#, type: .secret).lengthInBytes == 8160)
        #expect(throws: DerivationError.outOfRange(field: "lengthInBytes", allowed: 1...8160)) { try Recipe(json: #"{"lengthInBytes":0}"#, type: .secret) }
        #expect(throws: DerivationError.outOfRange(field: "lengthInBytes", allowed: 1...8160)) { try Recipe(json: #"{"lengthInBytes":8192}"#, type: .secret) }
        #expect(throws: DerivationError.outOfRange(field: "lengthInBytes", allowed: 1...8160)) { try Recipe(json: #"{"lengthInBytes":4294967312}"#, type: .secret) }
    }

    @Test("integer fields must be JSON integers")
    func integerFields() {
        for json in [#"{"lengthInBytes":16.9}"#, #"{"lengthInBytes":true}"#, #"{"lengthInBytes":"16"}"#, #"{"lengthInBytes":null}"#, #"{"lengthInBytes":1e1}"#] {
            #expect(throws: DerivationError.wrongType(field: "lengthInBytes", expected: "an integer")) { try Recipe(json: json, type: .secret) }
        }
        #expect(throws: DerivationError.wrongType(field: "lengthInChars", expected: "an integer")) { try Recipe(json: #"{"lengthInChars":8.9}"#, type: .password) }
    }

    @Test("keys must be 32 bytes")
    func keyLength() {
        for type in [DerivableType.symmetricKey, .unsealingKey, .signingKey] {
            #expect(throws: DerivationError.lengthMustBe32(type)) { try Recipe(json: #"{"lengthInBytes":16}"#, type: type) }
        }
    }

    @Test("password length resolves from bits or words, and bytes follow the words")
    func passwordLength() throws {
        #expect(try Recipe(json: #"{"lengthInBits":90}"#, type: .password).lengthInWords == 10)
        #expect(try Recipe(json: #"{"lengthInBits":1}"#, type: .password).lengthInWords == 1)
        #expect(try Recipe(json: #"{"lengthInBits":9180}"#, type: .password).lengthInWords == 1020)
        #expect(try Recipe(json: #"{"lengthInWords":3}"#, type: .password).lengthInBytes == 24)
        #expect(try Recipe(json: #"{"lengthInBits":90,"lengthInWords":10}"#, type: .password).lengthInWords == 10)
        #expect(try Recipe(json: #"{"lengthInBytes":16}"#, type: .password).lengthInBytes == 120)
        #expect(try Recipe(json: #"{"wordList":"EN_1024_words_6_chars_max_ed_4_20200917"}"#, type: .password).lengthInWords == 13)
        #expect(try Recipe(json: #"{"wordList":"EN_1024_words_6_chars_max_ed_4_20200917","lengthInBits":1}"#, type: .password).lengthInWords == 1)
        #expect(throws: DerivationError.bitsAndWordsConflict) { try Recipe(json: #"{"lengthInBits":1,"lengthInWords":9}"#, type: .password) }
        #expect(throws: DerivationError.outOfRange(field: "lengthInWords", allowed: 1...1020)) { try Recipe(json: #"{"lengthInWords":0}"#, type: .password) }
        #expect(throws: DerivationError.outOfRange(field: "lengthInWords", allowed: 1...1020)) { try Recipe(json: #"{"lengthInWords":1021}"#, type: .password) }
        #expect(throws: DerivationError.outOfRange(field: "lengthInBits", allowed: 1...9180)) { try Recipe(json: #"{"lengthInBits":0}"#, type: .password) }
        #expect(throws: DerivationError.outOfRange(field: "lengthInBits", allowed: 1...9180)) { try Recipe(json: #"{"lengthInBits":9181}"#, type: .password) }
        #expect(throws: DerivationError.outOfRange(field: "lengthInBits", allowed: 1...10200)) { try Recipe(json: #"{"wordList":"EN_1024_words_6_chars_max_ed_4_20200917","lengthInBits":10201}"#, type: .password) }
        #expect(throws: DerivationError.unknownWordList("nonsense")) { try Recipe(json: #"{"wordList":"nonsense"}"#, type: .password) }
    }

    @Test("lengthInChars is 1 or more")
    func lengthInChars() throws {
        #expect(try Recipe(json: #"{"lengthInChars":1}"#, type: .password).lengthInChars == 1)
        #expect(try Recipe(json: #"{"lengthInChars":64}"#, type: .password).lengthInChars == 64)
        #expect(throws: DerivationError.outOfRange(field: "lengthInChars", allowed: 1...Int.max)) { try Recipe(json: #"{"lengthInChars":0}"#, type: .password) }
        #expect(throws: DerivationError.outOfRange(field: "lengthInChars", allowed: 1...Int.max)) { try Recipe(json: #"{"lengthInChars":-1}"#, type: .password) }
    }

    @Test("password-only fields are salt on other types and are not validated there")
    func passwordFieldsElsewhere() throws {
        #expect(try Recipe(json: #"{"lengthInChars":0,"lengthInWords":0,"wordList":"nonsense"}"#, type: .secret).lengthInBytes == 32)
    }

    @Test("malformed JSON is reported with the parser's reason")
    func malformed() {
        #expect(throws: DerivationError.recipeNotAnObject) { try Recipe(json: "[]", type: .secret) }
        #expect(throws: DerivationError.recipeNotAnObject) { try Recipe(json: " ", type: .secret) }
        #expect(throws: DerivationError.duplicateField("lengthInBytes")) { try Recipe(json: #"{"lengthInBytes":16,"lengthInBytes":8}"#, type: .secret) }
        #expect(throws: DerivationError.invalidJson("Not valid JSON near position 4")) { try Recipe(json: "{not json", type: .secret) }
    }

    @Test("every error has a message")
    func messages() {
        let errors: [DerivationError] = [
            .recipeNotAnObject, .invalidJson("x"), .duplicateField("a"), .wrongType(field: "a", expected: "an integer"),
            .outOfRange(field: "a", allowed: 1...2), .typeMismatch(recipe: "Secret", requested: .password), .invalidAlgorithm("x"),
            .unsupportedHashFunction("x"), .unknownWordList("x"), .lengthMustBe32(.signingKey), .bitsAndWordsConflict,
            .engineRejected("x"), .internalError("x")
        ]
        for error in errors {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
        #expect(DerivationError.unsupportedHashFunction("Argon2id").errorDescription == "The hash function Argon2id is not supported; only BLAKE2b is")
        #expect(DerivationError.outOfRange(field: "lengthInBytes", allowed: 1...8160).errorDescription == "lengthInBytes must be between 1 and 8160")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

`cd Packages/Derivation && swift test -c release -Xswiftc -enable-testing --filter RecipeTests`. Expected: compile errors (`Recipe`, `DerivableType` not found).

- [ ] **Step 3: Write the types**

`Packages/Derivation/Sources/Derivation/DerivableType.swift`:

```swift
//
//  DerivableType.swift
//  Derivation
//

/// The kinds of value a recipe can derive. The raw values are the `type` strings of the
/// recipe format and of the JSON the derived values print, so they cannot change.
public enum DerivableType: String, Codable, CaseIterable, Identifiable, Sendable {
    case password = "Password"
    case secret = "Secret"
    case signingKey = "SigningKey"
    case symmetricKey = "SymmetricKey"
    case unsealingKey = "UnsealingKey"

    public var id: String { rawValue }
}
```

`HashFunction.swift`:

```swift
//
//  HashFunction.swift
//  Derivation
//

/// The hash a recipe's `hashFunction` field may name. One case for now; adding one is a
/// case here and an implementation in the engine. An unknown name is an error, never a
/// fallback, because the name is part of what gets hashed.
public enum HashFunction: String, Sendable {
    case blake2b = "BLAKE2b"
}
```

`WordList.swift`:

```swift
//
//  WordList.swift
//  Derivation
//

/// The word lists a password recipe may name. Sizes are powers of two because a word is
/// chosen as an 8-byte block modulo the list size.
public enum WordList: String, CaseIterable, Sendable {
    case en512 = "EN_512_words_5_chars_max_ed_4_20200917"
    case en1024 = "EN_1024_words_6_chars_max_ed_4_20200917"

    public var count: Int {
        switch self {
        case .en512: return 512
        case .en1024: return 1024
        }
    }

    public var bitsPerWord: Int {
        switch self {
        case .en512: return 9
        case .en1024: return 10
        }
    }
}
```

`DerivationError.swift`:

```swift
//
//  DerivationError.swift
//  Derivation
//

import Foundation

/// Why a recipe cannot be used, or a derivation failed. The messages are shown to the
/// user, so they say what to change.
public enum DerivationError: Error, Equatable, Sendable, LocalizedError {
    case recipeNotAnObject
    case invalidJson(String)
    case duplicateField(String)
    case wrongType(field: String, expected: String)
    case outOfRange(field: String, allowed: ClosedRange<Int>)
    case typeMismatch(recipe: String, requested: DerivableType)
    case invalidAlgorithm(String)
    case unsupportedHashFunction(String)
    case unknownWordList(String)
    case lengthMustBe32(DerivableType)
    case bitsAndWordsConflict
    /// The engine refused a recipe the parser accepted. Only the C++ engine does this, for
    /// the one check it gets wrong (a consistent lengthInBits and lengthInWords pair).
    case engineRejected(String)
    case internalError(String)

    public var errorDescription: String? {
        switch self {
        case .recipeNotAnObject:
            return "A recipe must be a JSON object, such as {\"purpose\":\"example\"}"
        case .invalidJson(let reason):
            return reason
        case .duplicateField(let name):
            return "The field \(name) appears more than once"
        case .wrongType(let field, let expected):
            return "\(field) must be \(expected)"
        case .outOfRange(let field, let allowed):
            if allowed.upperBound == Int.max {
                return "\(field) must be at least \(allowed.lowerBound)"
            }
            return "\(field) must be between \(allowed.lowerBound) and \(allowed.upperBound)"
        case .typeMismatch(let recipe, let requested):
            return "The recipe is for a \(recipe), not a \(requested.rawValue)"
        case .invalidAlgorithm(let name):
            return "The algorithm \(name) does not apply here"
        case .unsupportedHashFunction(let name):
            return "The hash function \(name) is not supported; only BLAKE2b is"
        case .unknownWordList(let name):
            return "Unknown word list \(name)"
        case .lengthMustBe32(let type):
            return "A \(type.rawValue) is always 32 bytes; leave lengthInBytes out or set it to 32"
        case .bitsAndWordsConflict:
            return "lengthInBits and lengthInWords disagree; give one or the other"
        case .engineRejected(let reason):
            return reason
        case .internalError(let reason):
            return "Derivation failed: \(reason)"
        }
    }
}
```

`Recipe.swift`:

```swift
//
//  Recipe.swift
//  Derivation
//

/// A recipe, parsed and validated. `json` is the text exactly as given, because that text
/// is what gets hashed; every other property is what the text means for `type`.
///
/// Parsing is strict where the reference C++ was lenient: integers must be JSON integers,
/// every length is bounded, and unknown names for `hashFunction`, `wordList` and
/// `algorithm` are errors. Fields the format defines for other types, and every field it
/// does not define, are salt only and are not read.
public struct Recipe: Sendable, Equatable {
    public let json: String
    public let type: DerivableType
    public let hashFunction: HashFunction
    /// The number of bytes the hash must produce: the secret's length, a key's 32, or a
    /// password's words times 8.
    public let lengthInBytes: Int
    public let lengthInChars: Int?
    public let wordList: WordList
    /// Password only; 0 for every other type.
    public let lengthInWords: Int

    /// The longest output the HKDF construction can produce: 255 blocks of 32 bytes.
    public static let maximumLengthInBytes = 8160
    public static let maximumLengthInWords = maximumLengthInBytes / 8

    public init(json: String, type: DerivableType) throws(DerivationError) {
        let fields = try Recipe.parse(json)
        self.json = json
        self.type = type

        if let declared = try fields.string("type"), declared != type.rawValue {
            throw .typeMismatch(recipe: declared, requested: type)
        }
        if let algorithm = try fields.string("algorithm") {
            let expected: String? = switch type {
            case .symmetricKey: "XSalsa20Poly1305"
            case .unsealingKey: "X25519"
            case .signingKey: "Ed25519"
            case .password, .secret: nil
            }
            guard algorithm == expected else { throw .invalidAlgorithm(algorithm) }
        }
        let hashName = try fields.string("hashFunction") ?? HashFunction.blake2b.rawValue
        guard let hashFunction = HashFunction(rawValue: hashName) else { throw .unsupportedHashFunction(hashName) }
        self.hashFunction = hashFunction

        switch type {
        case .password:
            let listName = try fields.string("wordList") ?? WordList.en512.rawValue
            guard let wordList = WordList(rawValue: listName) else { throw .unknownWordList(listName) }
            self.wordList = wordList
            let bitsPerWord = wordList.bitsPerWord
            let bitsRange = 1...(Recipe.maximumLengthInWords * bitsPerWord)
            let bits = try fields.integer("lengthInBits", in: bitsRange)
            let words = try fields.integer("lengthInWords", in: 1...Recipe.maximumLengthInWords)
            self.lengthInChars = try fields.integer("lengthInChars", in: 1...Int.max)
            // A lengthInBytes on a password is salt: the words decide the length.
            _ = try fields.integer("lengthInBytes", in: Int.min...Int.max)
            let resolvedWords: Int
            switch (bits, words) {
            case (nil, nil):
                resolvedWords = Recipe.wordsFor(bits: 128, bitsPerWord: bitsPerWord)
            case (nil, let words?):
                resolvedWords = words
            case (let bits?, nil):
                resolvedWords = Recipe.wordsFor(bits: bits, bitsPerWord: bitsPerWord)
            case (let bits?, let words?):
                guard words == Recipe.wordsFor(bits: bits, bitsPerWord: bitsPerWord) else { throw .bitsAndWordsConflict }
                resolvedWords = words
            }
            self.lengthInWords = resolvedWords
            self.lengthInBytes = resolvedWords * 8
        case .secret:
            self.lengthInBytes = try fields.integer("lengthInBytes", in: 1...Recipe.maximumLengthInBytes) ?? 32
            self.lengthInChars = nil
            self.wordList = .en512
            self.lengthInWords = 0
        case .symmetricKey, .unsealingKey, .signingKey:
            if let bytes = try fields.integer("lengthInBytes", in: Int.min...Int.max), bytes != 32 {
                throw .lengthMustBe32(type)
            }
            self.lengthInBytes = 32
            self.lengthInChars = nil
            self.wordList = .en512
            self.lengthInWords = 0
        }
    }

    private static func wordsFor(bits: Int, bitsPerWord: Int) -> Int {
        (bits + bitsPerWord - 1) / bitsPerWord
    }

    private static func parse(_ json: String) throws(DerivationError) -> RecipeFields {
        if json.isEmpty { return RecipeFields(fields: []) }
        do {
            return RecipeFields(fields: try RecipeJsonParser.parseObject(json))
        } catch {
            switch error {
            case .notAnObject: throw .recipeNotAnObject
            case .duplicateKey(let name, _): throw .duplicateField(name)
            case .invalid, .unrepresentableKey: throw .invalidJson(error.message)
            }
        }
    }
}

/// Typed access to the parsed fields, reading each one at most once.
private struct RecipeFields {
    let fields: [RecipeJsonField]

    func string(_ name: String) throws(DerivationError) -> String? {
        guard let field = fields.first(where: { $0.name == name }) else { return nil }
        guard case .string(let quoted) = field.value else { throw .wrongType(field: name, expected: "a string") }
        do {
            return try RecipeJsonParser.decodeString(quoted: quoted)
        } catch {
            throw .invalidJson(error.message)
        }
    }

    func integer(_ name: String, in allowed: ClosedRange<Int>) throws(DerivationError) -> Int? {
        guard let field = fields.first(where: { $0.name == name }) else { return nil }
        guard case .number(let text) = field.value, let value = Int(text) else {
            throw .wrongType(field: name, expected: "an integer")
        }
        guard allowed.contains(value) else { throw .outOfRange(field: name, allowed: allowed) }
        return value
    }
}
```

Notes for the implementer: the `switch` used as an expression (`let expected: String? = switch type {...}`) needs Swift 5.9 or later, fine here. `RecipeJsonError` has exactly the cases `notAnObject`, `invalid(offset:)`, `unrepresentableKey(offset:)` and `duplicateKey(name:offset:)` after Task 1; the `switch error` must be exhaustive over them. `Int("4294967312")` is a valid `Int` on 64-bit, so the out-of-range path is what rejects it.

- [ ] **Step 4: Run to verify they pass**

Same filter command; expected: all `RecipeTests` pass. Then `swiftlint lint --strict --quiet` from the worktree root: silent.

- [ ] **Step 5: Commit**

```bash
git add Packages/Derivation/Sources/Derivation Packages/Derivation/Tests/DerivationTests/RecipeTests.swift
git commit -m "Parse and validate recipes strictly"
```

---

### Task 3: The engine seam, the legacy engine, and the derived types

**Files:**
- Create: `Packages/Derivation/Sources/Derivation/DerivationEngine.swift`, `LegacyEngine.swift`, `Derived.swift`, `Hex.swift`
- Move: `Packages/SeededCrypto/Tests/SeededCryptoTests/Fixtures/vectors.json` → `Packages/Derivation/Tests/DerivationTests/Fixtures/vectors.json` (delete the placeholder `README.md`)
- Move and rewrite: `Packages/SeededCrypto/Tests/SeededCryptoTests/VectorTests.swift` → `Packages/Derivation/Tests/DerivationTests/VectorTests.swift`
- Modify: `Packages/SeededCrypto/Package.swift` (test target loses `resources`), `Packages/SeededCrypto/Tests/SeededCryptoTests/EmptyRecipeTests.swift:17,25` and `ConcurrentFirstUseTests.swift:19` (seed constant), `scripts/generate-vectors.sh` (`OUT` path)

**Interfaces:**
- Consumes: `Recipe`, `DerivableType`, `DerivationError`, `SeededCrypto` (`Password.deriveFromSeed` etc.).
- Produces:
```swift
protocol DerivationEngine: Sendable { func derive(_ type: DerivableType, seed: String, recipe: String) throws(DerivationError) -> String }  // the toJson() text
let defaultEngine: any DerivationEngine
struct LegacyEngine: DerivationEngine
public struct Password { public let password: String; public let recipe: Recipe; public static func derive(seed:recipe:) throws(DerivationError) -> Password; public func toJson() -> String }
public struct Secret { public let bytes: Data; ... }
public struct SymmetricKey { public let keyBytes: Data; ... }
public struct UnsealingKey { public let unsealingKeyBytes: Data; public let sealingKeyBytes: Data; ... }
public struct SigningKey { public let signingKeyBytes: Data; public var verificationKeyBytes: Data; ... }
extension Data { init?(hex: String) }  // internal
```

- [ ] **Step 1: Move the fixture and write the failing tests**

```bash
git mv Packages/SeededCrypto/Tests/SeededCryptoTests/Fixtures/vectors.json Packages/Derivation/Tests/DerivationTests/Fixtures/vectors.json
git rm Packages/Derivation/Tests/DerivationTests/Fixtures/README.md
git mv Packages/SeededCrypto/Tests/SeededCryptoTests/VectorTests.swift Packages/Derivation/Tests/DerivationTests/VectorTests.swift
```

In `scripts/generate-vectors.sh` change `OUT=` to `"$ROOT/Packages/Derivation/Tests/DerivationTests/Fixtures/vectors.json"`, and update the path named in the header comment of `scripts/generate-vectors.cpp` to match. In `Packages/SeededCrypto/Package.swift` remove `resources: [.copy("Fixtures")]` from the test target (and the trailing comma issue that leaves). In `EmptyRecipeTests.swift` and `ConcurrentFirstUseTests.swift` replace `fixture.exampleDiceKeySeed` with `exampleDiceKeySeed`, and add to `EmptyRecipeTests.swift` at file scope:

```swift
/// `DiceKey.Example`'s seed, the one every fixture entry that needs a DiceKey uses.
let exampleDiceKeySeed = "A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t"
```

Rewrite `Packages/Derivation/Tests/DerivationTests/VectorTests.swift` as:

```swift
//
//  VectorTests.swift
//  DerivationTests
//
//  Every value in Fixtures/vectors.json was produced by the reference C++ implementation
//  (scripts/generate-vectors.sh). If a `cases` or `legacy` test fails, derived passwords
//  and keys have changed for real users. Do not "fix" the fixture; fix the build.
//

import Foundation
import Testing
@testable import Derivation

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

    var derivableType: DerivableType? { DerivableType(rawValue: type) }
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
}

let fixture: VectorFixture = {
    let url = Bundle.module.url(forResource: "vectors", withExtension: "json", subdirectory: "Fixtures")!
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(VectorFixture.self, from: Data(contentsOf: url))
}()

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

@Suite("Derivation vectors from the reference C++")
struct VectorTests {
    @Test("the fixture holds the expected sections")
    func sections() {
        #expect(fixture.diceKeys.count == 4)
        #expect(fixture.cases.count == 168)
        #expect(fixture.legacy.count == 21)
        #expect(fixture.rejected.count == 16)
        #expect(fixture.legacy.allSatisfy { $0.note != nil })
    }

    @Test("every case derives to the recorded value through the public API", arguments: fixture.cases)
    func derives(vector: Vector) throws {
        let json = try #require(vector.json)
        switch try #require(vector.derivableType) {
        case .password:
            let password = try Password.derive(seed: vector.seed, recipe: vector.recipe)
            #expect(password.password == vector.password)
            #expect(password.toJson() == json)
            #expect(password.recipe.json == vector.recipe)
        case .secret:
            let secret = try Secret.derive(seed: vector.seed, recipe: vector.recipe)
            #expect(secret.bytes.hex == vector.secretBytesHex)
            #expect(secret.toJson() == json)
        case .symmetricKey:
            let key = try SymmetricKey.derive(seed: vector.seed, recipe: vector.recipe)
            #expect(key.keyBytes.hex == vector.keyBytesHex)
            #expect(key.toJson() == json)
        case .unsealingKey:
            let key = try UnsealingKey.derive(seed: vector.seed, recipe: vector.recipe)
            #expect(key.unsealingKeyBytes.hex == vector.unsealingKeyBytesHex)
            #expect(key.sealingKeyBytes.hex == vector.sealingKeyBytesHex)
            #expect(key.toJson() == json)
        case .signingKey:
            let key = try SigningKey.derive(seed: vector.seed, recipe: vector.recipe)
            #expect(key.signingKeyBytes.hex == vector.signingKeyBytesHex)
            #expect(key.verificationKeyBytes == key.signingKeyBytes.suffix(32))
            #expect(key.toJson() == json)
        }
    }

    // The strict parser refuses every legacy recipe; the engine behind it still produces
    // the recorded value, which is what lets the behavior be restored if ever wanted.
    @Test("every legacy entry is refused by the parser and still derived by the legacy engine", arguments: fixture.legacy)
    func legacy(vector: Vector) throws {
        let type = try #require(vector.derivableType)
        #expect(throws: DerivationError.self) { try Recipe(json: vector.recipe, type: type) }
        #expect(try LegacyEngine().derive(type, seed: vector.seed, recipe: vector.recipe) == vector.json)
    }

    @Test("every rejected entry throws", arguments: fixture.rejected)
    func rejects(vector: Vector) throws {
        let type = try #require(vector.derivableType)
        #expect(throws: DerivationError.self) {
            switch type {
            case .password: _ = try Password.derive(seed: vector.seed, recipe: vector.recipe)
            case .secret: _ = try Secret.derive(seed: vector.seed, recipe: vector.recipe)
            case .symmetricKey: _ = try SymmetricKey.derive(seed: vector.seed, recipe: vector.recipe)
            case .unsealingKey: _ = try UnsealingKey.derive(seed: vector.seed, recipe: vector.recipe)
            case .signingKey: _ = try SigningKey.derive(seed: vector.seed, recipe: vector.recipe)
            }
        }
    }

    @Test("the one check the C++ gets wrong surfaces as an engine rejection, not a parser error")
    func consistentBitsAndWords() {
        #expect(throws: DerivationError.engineRejected("lengthInBits and lengthInWords conflict")) {
            try Password.derive(seed: fixture.diceKeys[0].seed, recipe: #"{"lengthInBits":90,"lengthInWords":10}"#)
        }
    }

    @Test("the same recipe on the two orientation forms of one key derives different values")
    func orientationsMatter() throws {
        let key = fixture.diceKeys[0]
        let with = try Secret.derive(seed: key.seed, recipe: "")
        let without = try Secret.derive(seed: key.seedWithoutOrientations, recipe: "")
        #expect(with.bytes != without.bytes)
    }
}
```

The `consistentBitsAndWords` message must equal the C++'s `what()` for that case; it is recorded in the fixture's `rejected` entry named "consistent lengthInBits and lengthInWords" under `error`. Read it from the fixture (`python3 -c ...`) and use that exact text.

- [ ] **Step 2: Run to verify they fail**

`cd Packages/Derivation && swift test -c release -Xswiftc -enable-testing --filter VectorTests`. Expected: compile errors (`Password.derive` not found).

- [ ] **Step 3: Write the seam, the legacy engine and the derived types**

`Hex.swift`:

```swift
//
//  Hex.swift
//  Derivation
//

import Foundation

extension Data {
    /// Decodes lowercase or uppercase hex without a prefix; nil on odd length or a non-hex character.
    init?(hex: String) {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let high = Data.nibble(chars[index]), let low = Data.nibble(chars[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
            index += 2
        }
        self.init(bytes)
    }

    private static func nibble(_ char: UInt8) -> UInt8? {
        switch char {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return char - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return char - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return char - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}
```

`DerivationEngine.swift`:

```swift
//
//  DerivationEngine.swift
//  Derivation
//

/// What turns a seed and a recipe into a derived value. The output is the value's JSON in
/// the reference layout (see `Derived.swift`), because that is the one form every
/// implementation must agree on byte for byte.
///
/// This seam exists so the vendored C++ and its Swift replacement can be run over the same
/// vectors side by side. It goes away with the C++.
protocol DerivationEngine: Sendable {
    func derive(_ type: DerivableType, seed: String, recipe: String) throws(DerivationError) -> String
}

let defaultEngine: any DerivationEngine = LegacyEngine()
```

`LegacyEngine.swift`:

```swift
//
//  LegacyEngine.swift
//  Derivation
//

import SeededCrypto

/// The reference C++ (seeded-crypto over libsodium), reached through the SeededCrypto
/// package. Its own recipe parsing runs again inside, so anything the strict `Recipe`
/// accepted and the C++ still refuses surfaces as `engineRejected`.
struct LegacyEngine: DerivationEngine {
    func derive(_ type: DerivableType, seed: String, recipe: String) throws(DerivationError) -> String {
        do {
            switch type {
            case .password:
                return try SeededCrypto.Password.deriveFromSeed(withSeedString: seed, recipe: recipe).toJson()
            case .secret:
                return try SeededCrypto.Secret.deriveFromSeed(withSeedString: seed, recipe: recipe).toJson()
            case .symmetricKey:
                return try SeededCrypto.SymmetricKey.deriveFromSeed(withSeedString: seed, recipe: recipe).toJson()
            case .unsealingKey:
                return try SeededCrypto.UnsealingKey.deriveFromSeed(withSeedString: seed, recipe: recipe).toJson()
            case .signingKey:
                return try SeededCrypto.SigningKey.deriveFromSeed(withSeedString: seed, recipe: recipe).toJson()
            }
        } catch let error as SeededCryptoError {
            throw .engineRejected(error.message)
        } catch {
            throw .internalError(String(describing: error))
        }
    }
}
```

`Derived.swift`:

```swift
//
//  Derived.swift
//  Derivation
//
//  The five kinds of derived value. Each is built from the JSON its engine produced, in the
//  reference layout: keys in byte order, no whitespace, lowercase hex, and `recipe`
//  omitted when empty for Password, Secret and SymmetricKey but present for the key pairs.
//  `toJson()` returns that text unchanged because it is a displayed output format.
//

import Foundation

/// Decodes one engine JSON document into its fields, or reports what was wrong with it.
private func decodeFields<T: Decodable>(_ type: T.Type, from json: String) throws(DerivationError) -> T {
    do {
        return try JSONDecoder().decode(type, from: Data(json.utf8))
    } catch {
        throw .internalError("the engine produced unreadable JSON: \(error)")
    }
}

private func hexField(_ hex: String, named name: String) throws(DerivationError) -> Data {
    guard let data = Data(hex: hex) else { throw .internalError("the engine produced a non-hex \(name)") }
    return data
}

public struct Password: Sendable, Equatable {
    public let password: String
    public let recipe: Recipe
    private let json: String

    private struct Fields: Decodable { let password: String }

    public static func derive(seed: String, recipe: String) throws(DerivationError) -> Password {
        let parsed = try Recipe(json: recipe, type: .password)
        let json = try defaultEngine.derive(.password, seed: seed, recipe: recipe)
        return Password(password: try decodeFields(Fields.self, from: json).password, recipe: parsed, json: json)
    }

    public func toJson() -> String { json }
}

public struct Secret: Sendable, Equatable {
    public let bytes: Data
    public let recipe: Recipe
    private let json: String

    private struct Fields: Decodable { let secretBytes: String }

    public static func derive(seed: String, recipe: String) throws(DerivationError) -> Secret {
        let parsed = try Recipe(json: recipe, type: .secret)
        let json = try defaultEngine.derive(.secret, seed: seed, recipe: recipe)
        let fields = try decodeFields(Fields.self, from: json)
        return Secret(bytes: try hexField(fields.secretBytes, named: "secretBytes"), recipe: parsed, json: json)
    }

    public func toJson() -> String { json }
}

public struct SymmetricKey: Sendable, Equatable {
    public let keyBytes: Data
    public let recipe: Recipe
    private let json: String

    private struct Fields: Decodable { let keyBytes: String }

    public static func derive(seed: String, recipe: String) throws(DerivationError) -> SymmetricKey {
        let parsed = try Recipe(json: recipe, type: .symmetricKey)
        let json = try defaultEngine.derive(.symmetricKey, seed: seed, recipe: recipe)
        let fields = try decodeFields(Fields.self, from: json)
        return SymmetricKey(keyBytes: try hexField(fields.keyBytes, named: "keyBytes"), recipe: parsed, json: json)
    }

    public func toJson() -> String { json }
}

public struct UnsealingKey: Sendable, Equatable {
    public let unsealingKeyBytes: Data
    public let sealingKeyBytes: Data
    public let recipe: Recipe
    private let json: String

    private struct Fields: Decodable { let unsealingKeyBytes: String; let sealingKeyBytes: String }

    public static func derive(seed: String, recipe: String) throws(DerivationError) -> UnsealingKey {
        let parsed = try Recipe(json: recipe, type: .unsealingKey)
        let json = try defaultEngine.derive(.unsealingKey, seed: seed, recipe: recipe)
        let fields = try decodeFields(Fields.self, from: json)
        return UnsealingKey(
            unsealingKeyBytes: try hexField(fields.unsealingKeyBytes, named: "unsealingKeyBytes"),
            sealingKeyBytes: try hexField(fields.sealingKeyBytes, named: "sealingKeyBytes"),
            recipe: parsed,
            json: json
        )
    }

    public func toJson() -> String { json }
}

public struct SigningKey: Sendable, Equatable {
    /// The Ed25519 seed followed by the public key, 64 bytes, as libsodium lays it out.
    public let signingKeyBytes: Data
    public let recipe: Recipe
    private let json: String

    public var verificationKeyBytes: Data { signingKeyBytes.suffix(32) }

    private struct Fields: Decodable { let signingKeyBytes: String }

    public static func derive(seed: String, recipe: String) throws(DerivationError) -> SigningKey {
        let parsed = try Recipe(json: recipe, type: .signingKey)
        let json = try defaultEngine.derive(.signingKey, seed: seed, recipe: recipe)
        let fields = try decodeFields(Fields.self, from: json)
        let bytes = try hexField(fields.signingKeyBytes, named: "signingKeyBytes")
        guard bytes.count == 64 else { throw .internalError("the engine produced a \(bytes.count)-byte signing key") }
        return SigningKey(signingKeyBytes: bytes, recipe: parsed, json: json)
    }

    public func toJson() -> String { json }
}
```

Two things to watch: inside the `Derivation` module the names `Password`, `Secret`, `SymmetricKey`, `UnsealingKey`, `SigningKey` clash with `SeededCrypto`'s; `LegacyEngine.swift` qualifies every SeededCrypto use, and no other file imports SeededCrypto. `Data.suffix(32)` returns `Data` (a `SubSequence` of `Data` is `Data`), so `verificationKeyBytes` compares equal to a `Data` in the test.

- [ ] **Step 4: Run every test**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
(cd Packages/Derivation && swift test -c release -Xswiftc -enable-testing --parallel 2>&1 | tail -5)
(cd Packages/SeededCrypto && swift test -c release -Xswiftc -enable-testing --parallel 2>&1 | tail -5)
shellcheck scripts/*.sh
swiftlint lint --strict --quiet
```
Expected: Derivation: `RecipeJsonTests`, `RecipeTests`, `VectorTests` (168 derives, 21 legacy, 16 rejects) pass; SeededCrypto: `EmptyRecipeTests` and `ConcurrentFirstUseTests` pass; shellcheck and lint silent. Also run `./scripts/generate-vectors.sh` once and confirm `git status` shows the fixture unchanged at its new path.

- [ ] **Step 5: Commit**

```bash
git add -A Packages/Derivation Packages/SeededCrypto scripts/generate-vectors.sh
git commit -m "Derive through an engine seam, with the vendored C++ behind it"
```

---

### Task 4: KeyFormats: BIP39 moved, OpenSSH and OpenPGP forwarded

**Files:**
- Delete: `Packages/Derivation/Sources/KeyFormats/KeyFormats.swift`
- Create: `Packages/Derivation/Sources/KeyFormats/OpenSSH.swift`, `OpenPGP.swift`, `BIP39.swift`
- Move: `DiceKeys/Model/BIP39/Mnemonic.swift` → `Packages/Derivation/Sources/KeyFormats/Mnemonic.swift`; `DiceKeys/Model/BIP39/Wordlist.swift` → `.../KeyFormats/Wordlist.swift`
- Move: `Tests/DiceKeysTests/MnemonicsTests.swift` → `Packages/Derivation/Tests/DerivationTests/KeyFormatsTests.swift` (rewritten)
- Modify: `DiceKeys/Model/Recipes/DerivedValue.swift:72-73` (BIP39 call), `docs/ARCHITECTURE.md` wherever `Model/BIP39` is listed

**Interfaces:**
- Consumes: `Derivation.SigningKey` (`toJson()`), `SeededCrypto.SigningKey.from(json:)` and its export methods.
- Produces:
```swift
public enum OpenSSH { public static func publicKeyLine(_ key: SigningKey) throws -> String; public static func privateKeyPEM(_ key: SigningKey, comment: String = "") throws -> String }
public enum OpenPGP { public static func secretKeyBlock(_ key: SigningKey, userId: String = "", timestamp: UInt32 = 0) throws -> String }
public enum BIP39 { public enum Error: Swift.Error { case invalidEntropyLength(Int) }; public static func mnemonic(entropy: Data) throws -> String }
```

- [ ] **Step 1: Write the failing tests**

Move `Tests/DiceKeysTests/MnemonicsTests.swift` with `git mv` to `Packages/Derivation/Tests/DerivationTests/KeyFormatsTests.swift` and replace its contents with:

```swift
//
//  KeyFormatsTests.swift
//  DerivationTests
//

import Foundation
import Testing
import Derivation
import KeyFormats

@Suite("BIP39")
struct BIP39Tests {
    static let vectors: [(entropyHex: String, mnemonic: String)] = [
        ("00000000000000000000000000000000",
         "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"),
        ("7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f",
         "legal winner thank year wave sausage worth useful legal winner thank yellow"),
        ("066dca1a2bb7e8a1db2832148ce9933eea0f3ac9548d793112d9a95c9407efad",
         "all hour make first leader extend hole alien behind guard gospel lava path output census museum junior mass reopen famous sing advance salt reform"),
        ("f30f8c1da665478f49b001d94c5fc452",
         "vessel ladder alter error federal sibling chat ability sun glass valve picture"),
        ("c10ec20dc3cd9f652c7fac2f1230f7a3c828389a14392f05",
         "scissors invite lock maple supreme raw rapid void congress muscle digital elegant little brisk hair mango congress clump"),
        ("f585c11aec520db57dd353c69554b21a89b20fb0650966fa0a9d6f74fd989d8f",
         "void come effort suffer camp survey warrior heavy shoot primary clutch crush open amazing screen patrol group space point ten exist slush involve unfold")
    ]

    @Test("entropy bytes map to the BIP39 reference mnemonics", arguments: vectors)
    func referenceVectors(vector: (entropyHex: String, mnemonic: String)) throws {
        let entropy = try #require(Data(hexString: vector.entropyHex))
        #expect(try BIP39.mnemonic(entropy: entropy) == vector.mnemonic)
    }

    @Test("entropy must be 16 to 32 bytes in steps of 4")
    func entropyLength() {
        for count in [0, 15, 17, 33] {
            #expect(throws: BIP39.Error.invalidEntropyLength(count)) { try BIP39.mnemonic(entropy: Data(repeating: 0, count: count)) }
        }
    }
}

@Suite("Signing key exports from the reference C++")
struct ExportTests {
    static let signingCases = fixture.cases.filter { $0.type == "SigningKey" }

    @Test("OpenSSH and OpenPGP exports match the fixture", arguments: signingCases)
    func exports(vector: Vector) throws {
        let key = try SigningKey.derive(seed: vector.seed, recipe: vector.recipe)
        #expect(try OpenSSH.publicKeyLine(key) == vector.openSshPublicKey)
        let recorded = try #require(vector.openSshPemPrivateKey)
        let sshPrivate = try OpenSSH.privateKeyPEM(key, comment: vector.sshComment ?? "")
        #expect(sshPrivate.count == recorded.count)
        #expect(try maskedOpenSshKey(sshPrivate) == maskedOpenSshKey(recorded))
        let pgp = try OpenPGP.secretKeyBlock(key, userId: vector.pgpUserId ?? "", timestamp: vector.pgpTimestamp ?? 0)
        #expect(pgp == vector.openPgpPemFormatSecretKey)
    }
}

/// The binary body of an OpenSSH private key with its two check-int copies zeroed. The private
/// section starts after the magic, the cipher, KDF and KDF options strings, the key count, the
/// public key blob and the section length.
func maskedOpenSshKey(_ pem: String) throws -> [UInt8] {
    let body = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
    var bytes = [UInt8](try #require(Data(base64Encoded: body)))
    var offset = "openssh-key-v1\0".utf8.count
    func uint32(at index: Int) -> Int {
        bytes[index..<index + 4].reduce(0) { $0 << 8 | Int($1) }
    }
    for _ in 0..<3 { offset += 4 + uint32(at: offset) }
    offset += 4
    offset += 4 + uint32(at: offset)
    offset += 4
    for index in offset..<offset + 8 { bytes[index] = 0 }
    return bytes
}

private extension Data {
    init?(hexString: String) {
        let chars = Array(hexString.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var index = 0
        while index < chars.count {
            guard let byte = UInt8(String(decoding: chars[index..<index + 2], as: UTF8.self), radix: 16) else { return nil }
            bytes.append(byte)
            index += 2
        }
        self.init(bytes)
    }
}
```

If Task 3 left a `maskedOpenSshKey` in `VectorTests.swift`, delete it there; this file's copy is the one (it is file-scope and internal, visible to the whole test target).

- [ ] **Step 2: Run to verify they fail**

`cd Packages/Derivation && swift test -c release -Xswiftc -enable-testing --filter 'BIP39Tests|ExportTests'`. Expected: compile errors (`BIP39`, `OpenSSH` not found).

- [ ] **Step 3: Write KeyFormats**

Delete `Packages/Derivation/Sources/KeyFormats/KeyFormats.swift`. `git mv DiceKeys/Model/BIP39/Mnemonic.swift Packages/Derivation/Sources/KeyFormats/Mnemonic.swift` and `git mv DiceKeys/Model/BIP39/Wordlist.swift Packages/Derivation/Sources/KeyFormats/Wordlist.swift`. In both, drop `public` everywhere (they are internal to `KeyFormats`) and change the `//  DiceKeys (iOS)` header line in `Wordlist.swift` to `//  KeyFormats`. In `Mnemonic.swift` change `public class Mnemonic` to `enum Mnemonic` (it has only static members) and remove the unused `Error` enum and the `toMnemonic` `wordlist` parameter default is fine to keep.

`BIP39.swift`:

```swift
//
//  BIP39.swift
//  KeyFormats
//

import Foundation

/// A BIP39 mnemonic for a derived secret: the standard way to carry a wallet seed.
public enum BIP39 {
    public enum Error: Swift.Error, Equatable {
        /// BIP39 allows 128 to 256 bits of entropy in 32-bit steps.
        case invalidEntropyLength(Int)
    }

    public static func mnemonic(entropy: Data) throws -> String {
        guard (16...32).contains(entropy.count), entropy.count % 4 == 0 else {
            throw Error.invalidEntropyLength(entropy.count)
        }
        return Mnemonic.toMnemonic([UInt8](entropy)).joined(separator: " ")
    }
}
```

`Mnemonic.toMnemonic` currently `throws` but never does; make it non-throwing (remove `throws` and the `try` in `BIP39`). If SwiftLint's `force_unwrapping` is not enabled the existing `Int(..., radix: 2)!` stays.

`OpenSSH.swift`:

```swift
//
//  OpenSSH.swift
//  KeyFormats
//

import Derivation
import SeededCrypto

/// The OpenSSH encodings of an Ed25519 signing key. The vendored C++ produces them until
/// the Swift encoder lands.
public enum OpenSSH {
    /// One line: `ssh-ed25519 <base64> DiceKeys`.
    public static func publicKeyLine(_ key: SigningKey) throws -> String {
        try SeededCrypto.SigningKey.from(json: key.toJson()).openSshPublicKey
    }

    /// An unencrypted `openssh-key-v1` block, with the comment stored inside it.
    public static func privateKeyPEM(_ key: SigningKey, comment: String = "") throws -> String {
        try SeededCrypto.SigningKey.from(json: key.toJson()).openSshPemPrivateKey(comment: comment)
    }
}
```

`OpenPGP.swift`:

```swift
//
//  OpenPGP.swift
//  KeyFormats
//

import Derivation
import SeededCrypto

/// The OpenPGP secret key block for an Ed25519 signing key. The vendored C++ produces it
/// until the Swift encoder lands.
public enum OpenPGP {
    /// Timestamp 0 keeps the fingerprint stable across derivations; the fingerprint hashes
    /// the creation time.
    public static func secretKeyBlock(_ key: SigningKey, userId: String = "", timestamp: UInt32 = 0) throws -> String {
        try SeededCrypto.SigningKey.from(json: key.toJson()).openPgpPemFormatSecretKey(userId: userId, timestamp: timestamp)
    }
}
```

`DiceKeys/Model/Recipes/DerivedValue.swift`: add `import KeyFormats` and change the BIP39 line to
```swift
            return (try? BIP39.mnemonic(entropy: secret.secretBytes())) ?? secret.secretBytes().asHexString
```
(`secret` is still the SeededCrypto type until Task 5). `docs/ARCHITECTURE.md`: remove the `Model/BIP39` line from the directory tree if present and, in the package list, mention `KeyFormats` beside `Derivation` (one line).

- [ ] **Step 4: Run every test**

Package tests (both packages), then the app tests and lint and analyze as in Task 1 Step 4 (add the analyze commands from Global Constraints). Expected: `BIP39Tests` 7 tests and `ExportTests` one per SigningKey case (22) pass alongside the rest; the app builds and `DiceKeysTests` passes; lint and analyze silent (the app no longer has `Mnemonic`).

- [ ] **Step 5: Commit**

```bash
git add -A Packages/Derivation DiceKeys/Model/BIP39 DiceKeys/Model/Recipes/DerivedValue.swift Tests/DiceKeysTests docs/ARCHITECTURE.md
git commit -m "Add KeyFormats with BIP39 and the exports the C++ still produces"
```

---

### Task 5: Switch the app to the package

**Files:**
- Delete: `DiceKeys/Model/Recipes/SeededCryptoRecipeType.swift`; create `DiceKeys/Model/Recipes/DerivableType+Descriptions.swift`
- Modify: `DerivationRecipe.swift`, `DerivedValue.swift`, `DiceKey.swift:11,225`, `DerivationRecipeTemplates.swift`, `CustomRecipeModel.swift`, `CustomRecipeForm.swift`, `DerivedValueScreen.swift`, `RecipeListView.swift:36`, `project.yml`
- Delete: `Tests/DiceKeysTests/PasswordDerivationTests.swift`
- Modify: `Tests/DiceKeysTests/RecipeBuildingTests.swift`, `DiceKeySeedTests.swift:13`, `DefaultOutputFormatTests.swift`

**Interfaces:**
- Consumes: `Derivation.DerivableType`, `Password.derive` and the other four, `DerivationError`, `KeyFormats.OpenSSH`, `OpenPGP`, `BIP39`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/DiceKeysTests/RecipeBuildingTests.swift` inside the suite:

```swift
    @Test("stored recipes still decode with the package's type names")
    func storedRecipeDecodes() throws {
        let stored = #"[{"type":"Password","name":"n","recipe":"{\"purpose\":\"x\"}"},{"type":"SigningKey","name":"k","recipe":""}]"#
        let recipes = try #require(try DerivationRecipe.listFromJson(stored))
        #expect(recipes.map(\.type) == [.password, .signingKey])
        #expect(try DerivationRecipe.listToJson(recipes).contains(#""type":"Password""#))
    }

    @Test("a stored recipe the strict parser rejects reports why instead of deriving")
    func rejectedRecipeReports() {
        let recipe = DerivationRecipe(type: .secret, name: "old", recipe: #"{"lengthInBytes":16.9}"#)
        #expect(throws: DerivationError.wrongType(field: "lengthInBytes", expected: "an integer")) {
            try recipe.derivedValue(diceKey: DiceKey.Example)
        }
    }

    @Test("the custom builder starts on purpose and has no web address mode")
    @MainActor
    func builderModes() {
        let model = CustomRecipeModel(type: .password)
        #expect(model.buildType == .purpose)
        #expect(RecipeBuildType.allCases == [.purpose, .rawJson])
    }
```

and delete the `hostsRecipe` test. Replace every `.Password` with `.password` in this file. Add `import Derivation` at the top.

- [ ] **Step 2: Run to verify they fail**

App tests filtered to `RecipeBuildingTests`. Expected: compile errors (`.password`, `RecipeBuildType.allCases`).

- [ ] **Step 3: Make the switch**

1. `git rm DiceKeys/Model/Recipes/SeededCryptoRecipeType.swift`; create `DiceKeys/Model/Recipes/DerivableType+Descriptions.swift`:

```swift
//
//  DerivableType+Descriptions.swift
//  DiceKeys
//

import Derivation

extension DerivableType {
    var description: String {
        switch self {
        case .password: return "Password"
        case .secret: return "Secret"
        case .signingKey: return "Signing Key"
        case .symmetricKey: return "Symmetric Key"
        case .unsealingKey: return "Unsealing Key"
        }
    }

    var descriptionForRecipeBuilder: String {
        switch self {
        case .password: return "password"
        case .secret: return "seed or other secret"
        case .signingKey: return "signing/authentication key"
        case .symmetricKey: return "symmetric cryptographic key"
        case .unsealingKey: return "public/private key pair"
        }
    }
}
```

2. Rename in the app: `SeededCryptoRecipeType` → `DerivableType` everywhere (`grep -rn SeededCryptoRecipeType DiceKeys Tests`), and the cases `.Password`/`.Secret`/`.SigningKey`/`.SymmetricKey`/`.UnsealingKey` → lowercase where they refer to the recipe type (the `grep` in the file list above shows every site: `CustomRecipeModel.swift:119-120`, `CustomRecipeForm.swift:59,64,102`, `DerivationRecipe.swift:58,65,66,85-94,104-106`, `DerivationRecipeTemplates.swift` (12), `RecipeBuildingTests.swift`). `DerivedValueView` also has a `.Password` case; leave those (`DerivedValue.swift`, `DerivationRecipe.swift:104-106` right-hand sides, `DefaultOutputFormatTests.swift`).

3. `DerivationRecipe.swift`: replace `import SeededCrypto` with nothing (keep `import Derivation`); delete `getRecipeJson(hosts:...)`; rewrite `derivedValue(diceKey:)`:

```swift
    /// Throws when the recipe is not valid, which a hand-edited raw JSON recipe or one
    /// saved before validation existed can be; the message says what is wrong.
    func derivedValue(diceKey: DiceKey) throws -> any DerivedValue {
        let seed = diceKey.toSeed()
        switch type {
        case .password:
            return DerivedValuePassword(password: try Password.derive(seed: seed, recipe: recipe))
        case .secret:
            let lengthInBytes = lengthInBytes()
            return DerivedValueSecret(secret: try Secret.derive(seed: seed, recipe: recipe), showBIP39: lengthInBytes == nil || lengthInBytes == 32)
        case .signingKey:
            return try DerivedValueSigningKey(signingKey: try SigningKey.derive(seed: seed, recipe: recipe))
        case .symmetricKey:
            return DerivedValueSymmetricKey(symmetricKey: try SymmetricKey.derive(seed: seed, recipe: recipe))
        case .unsealingKey:
            return DerivedValueUnsealingKey(unsealingKey: try UnsealingKey.derive(seed: seed, recipe: recipe))
        }
    }
```

4. `DerivedValue.swift`: `import Derivation` and `import KeyFormats` replace `import SeededCrypto`. `DerivedValueSecret` uses `secret.bytes` in place of `secret.secretBytes()`. `DerivedValueSigningKey` becomes:

```swift
struct DerivedValueSigningKey: DerivedValue {
    let signingKey: SigningKey
    let openPgpSecretKey: String
    let openSshPrivateKey: String
    let openSshPublicKey: String

    var views: [DerivedValueView] = [.JSON, .OpenPGPPrivateKey, .OpenSSHPrivateKey, .OpenSSHPublicKey, .HexSigningKey]

    init(signingKey: SigningKey) throws {
        self.signingKey = signingKey
        openPgpSecretKey = try OpenPGP.secretKeyBlock(signingKey)
        openSshPrivateKey = try OpenSSH.privateKeyPEM(signingKey)
        openSshPublicKey = try OpenSSH.publicKeyLine(signingKey)
    }

    func valueForView(view: DerivedValueView) -> String {
        switch view {
        case .OpenPGPPrivateKey: return openPgpSecretKey
        case .OpenSSHPrivateKey: return openSshPrivateKey
        case .OpenSSHPublicKey: return openSshPublicKey
        case .HexSigningKey: return signingKey.signingKeyBytes.asHexString
        default: return signingKey.toJson()
        }
    }
}
```

5. `DiceKey.swift`: `import Derivation` replaces `import SeededCrypto`; line 225 becomes `let bytes = try! Secret.derive(seed: toSeed(), recipe: recipeFor16ByteUniqueIdentifier).bytes` (keep the existing `swiftlint:disable:next force_try` line and its comment).

6. Remove hosts mode. `CustomRecipeModel.swift`: `enum RecipeBuildType: CaseIterable { case purpose, rawJson }`; `buildType` default `.purpose`; delete `urlString`, `hosts`, the `.hosts` arms of `name` and both switches in `update()`. `CustomRecipeForm.swift`: remove the `.hosts` arm of `explanation`, the "Web Address" picker entry, the `.hosts` text field case, and make the alert's Cancel set `model.buildType = .purpose`.

7. `DerivedValueScreen.swift`: `private var diceKey: DiceKey? { diceKeyMemoryStore.diceKeyLoaded }`; in `onChange`, `derivedValue = try diceKey.flatMap { try recipe?.derivedValue(diceKey: $0) }`; in the body, `if let derivedValue, let diceKey { DerivedValueOutputView(diceKey: diceKey, ...) }`. Update the doc comment: "Derives ... from the foreground DiceKey; shows nothing when no DiceKey is loaded."

8. `RecipeListView.swift:36`: `ForEach(DerivableType.allCases)`.

9. `project.yml`: remove the two `SeededCrypto` dependency entries (app and tests) and the `SeededCrypto:` package entry; the package comment from Task 1 stays accurate (Derivation depends on SeededCrypto internally).

10. Tests: `git rm Tests/DiceKeysTests/PasswordDerivationTests.swift` (its behavior is now `RecipeTests.lengthInChars` and the fixture's legacy entry). `DiceKeySeedTests.swift`: remove `import SeededCrypto`. `DefaultOutputFormatTests.swift`: unchanged unless it fails to compile.

- [ ] **Step 4: Run everything**

Both package test suites, the whole `DiceKeysTests` target, `swiftlint lint --strict --quiet`, the analyze check. Expected: all green and silent; `DiceKeySeedTests.diceKeyId` still passes (Review Focus 3).

- [ ] **Step 5: Commit**

```bash
git add -A DiceKeys Tests project.yml
git commit -m "Derive through the Derivation package, and drop the web address recipe mode"
```

---

### Task 6: Docs and the pull request

**Files:**
- Modify: `docs/ARCHITECTURE.md` (package section and directory tree), `docs/DEPENDENCIES.md` (one sentence: the app reaches SeededCrypto through Derivation)
- Modify: `docs/superpowers/specs/2026-09-29-derivation-rewrite-design.md`: none, unless a decision changed.

- [ ] **Step 1: Update the docs**

`grep -n "SeededCrypto\|Packages/" docs/ARCHITECTURE.md docs/DEPENDENCIES.md README.md`. In `ARCHITECTURE.md`: the packages paragraph lists three packages with one line each (`Derivation`: recipes, derived values, the engine seam, `KeyFormats`; `SeededCrypto`: the vendored C++ behind it, going away; `ReadDiceKey`); the directory tree drops `SeededCryptoRecipeType` and `Model/BIP39` and names `DerivableType+Descriptions`. In `DEPENDENCIES.md` line 4 area: one clause that the app no longer imports `SeededCrypto` directly. Keep every edit to a line or two; do not add sections.

- [ ] **Step 2: Verify**

`swiftlint lint --strict --quiet`; `actionlint`; and the full app test run once more.

- [ ] **Step 3: Commit and push**

```bash
git add docs
git commit -m "Describe the Derivation package in the architecture doc"
git push -u origin derivation-package
```

- [ ] **Step 4: Open the PR** (base `derivation-vectors`)

Title: `Put the app behind a Derivation package, with the C++ still deriving`

Body:
```
The app called the vendored C++ wrapper directly, so nothing could replace the C++ without touching every screen. Now the app talks to a Derivation package whose public API is the one the Swift engine will implement; the C++ sits behind an internal engine protocol.

## Decisions

- Recipe parsing is strict now, ahead of the Swift engine: integers must be integers, every length is bounded, unknown hash function, word list and algorithm names are errors. The 21 legacy fixture entries prove the parser refuses exactly the inputs the port drops, and that the C++ behind it still derives them.
- The recipe JSON parser moved from the app into the package, so the canonicalizer and the validator share one parser.
- Signing key exports and BIP39 live in a KeyFormats product; the exports still forward to the C++ until the Swift encoders land.
- The web address recipe mode is gone. The allow field it wrote is only enforced by the inter-app API, which this app does not have; a site name goes in the purpose.
- The derive screen shows nothing when no DiceKey is loaded, instead of deriving from the example key.

Verified: all 168 fixture cases through the public API, 21 legacy entries through the engine, 16 rejections; the app's own suites including the DiceKey id vector.
```
