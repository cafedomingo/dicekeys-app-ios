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
#include "key-formats/OpenSshKey.hpp"
#include "signing-key.hpp"
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
        // The check value is random in the library and pinned here so the fixture regenerates without a diff.
        v["sshComment"] = c.sshComment;
        v["openSshPemPrivateKey"] = getOpenSshPemPrivateKeyEd25519(SigningKey::fromJson(js), c.sshComment, 0);
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
