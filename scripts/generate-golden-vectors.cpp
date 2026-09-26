// Generates Packages/DiceKeysCore/Tests/SeededCryptoTests/Fixtures/golden-vectors.json
// straight from the reference C++ (lib-seeded + libsodium) through the C ABI shim.
// Build + run on any machine with clang++; see scripts/generate-golden-vectors.sh.
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>
#include "SeededCryptoNative.h"
#include "github-com-nlohmann-json/json.hpp"

using nlohmann::json;

static std::string take(char *s) { std::string r = s ? s : ""; dkc_free(s); return r; }
static std::string hex(dkc_bytes b) {
    static const char *d = "0123456789abcdef"; std::string r;
    for (size_t i = 0; i < b.length; i++) { r += d[b.data[i] >> 4]; r += d[b.data[i] & 15]; }
    dkc_bytes_free(b); return r;
}
static std::string must(int ok, char *err, const char *what) {
    if (!ok) { fprintf(stderr, "%s failed: %s\n", what, err ? err : "?"); exit(1); }
    return "";
}

int main() {
    const std::string exampleSeed = "A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t";
    struct Case { const char *name; const char *type; const char *seed; const char *recipe; };
    std::vector<Case> cases = {
        {"template 1Password", "Password", exampleSeed.c_str(), "{\"allow\":[{\"host\":\"*.1password.com\"}]}"},
        {"template Apple 64 chars", "Password", exampleSeed.c_str(), "{\"allow\":[{\"host\":\"*.apple.com\"},{\"host\":\"*.icloud.com\"}],\"lengthInChars\":64}"},
        {"template Bitwarden", "Password", exampleSeed.c_str(), "{\"allow\":[{\"host\":\"*.bitwarden.com\"}]}"},
        {"template Google sequence 2", "Password", exampleSeed.c_str(), "{\"allow\":[{\"host\":\"*.google.com\"}],\"#\":2}"},
        {"issue 56 lengthInChars 0", "Password", "this string is seedy", "{\"allow\":[{\"host\":\"*.exampl.com\"}],\"lengthInChars\":0}"},
        {"template wallet secret", "Secret", exampleSeed.c_str(), "{\"purpose\":\"wallet\"}"},
        {"wallet 32 bytes explicit", "Secret", exampleSeed.c_str(), "{\"purpose\":\"wallet\",\"lengthInBytes\":32}"},
        {"DiceKey 16 byte id", "Secret", exampleSeed.c_str(), "{\"purpose\":\"a unique identifier for this DiceKey\",\"lengthInBytes\":16}"},
        {"template ssh", "SigningKey", exampleSeed.c_str(), "{\"purpose\":\"ssh\"}"},
        {"template pgp", "SigningKey", exampleSeed.c_str(), "{\"purpose\":\"pgp\"}"},
        {"symmetric key", "SymmetricKey", exampleSeed.c_str(), "{\"purpose\":\"symmetric test\"}"},
        {"unsealing key", "UnsealingKey", exampleSeed.c_str(), "{\"purpose\":\"unsealing test\"}"},
    };
    json out;
    out["exampleDiceKeySeed"] = exampleSeed;
    out["exampleDiceKeySeedWithoutOrientations"] = "A1B2C3D4E5F6G1H2I3J4K5L6M1N2O3P4R5S6T1U2V3W4X5Y6Z1";
    out["sodiumVersion"] = dkc_sodium_version();
    json vectors = json::array();
    const std::string message = "The quick brown fox jumps over the lazy dog";
    const uint8_t *msg = reinterpret_cast<const uint8_t *>(message.data());
    for (auto &c : cases) {
        json v; v["name"] = c.name; v["type"] = c.type; v["seed"] = c.seed; v["recipe"] = c.recipe;
        char *j = nullptr, *err = nullptr, *s = nullptr;
        std::string type = c.type;
        must(dkc_recipe_with_all_optional_parameters_specified(c.recipe, &s, &err), err, c.name);
        v["recipeWithAllOptionalParametersSpecified"] = take(s);
        if (type == "Password") {
            must(dkc_password_derive(c.seed, c.recipe, &j, &err), err, c.name);
            std::string js = take(j); v["json"] = js; v["password"] = json::parse(js)["password"];
        } else if (type == "Secret") {
            must(dkc_secret_derive(c.seed, c.recipe, &j, &err), err, c.name);
            std::string js = take(j); v["json"] = js; v["secretBytesHex"] = json::parse(js)["secretBytes"];
        } else if (type == "SigningKey") {
            must(dkc_signing_key_derive(c.seed, c.recipe, &j, &err), err, c.name);
            std::string js = take(j); v["json"] = js;
            must(dkc_signing_key_signature_verification_key(js.c_str(), &s, &err), err, c.name); v["signatureVerificationKeyJson"] = take(s);
            must(dkc_signing_key_open_ssh_public_key(js.c_str(), &s, &err), err, c.name); v["openSshPublicKey"] = take(s);
            must(dkc_signing_key_open_ssh_pem_private_key(js.c_str(), "", &s, &err), err, c.name); v["openSshPemPrivateKey"] = take(s); // random check value inside; tests compare shape only
            must(dkc_signing_key_open_pgp_pem_secret_key(js.c_str(), "", 0, &s, &err), err, c.name); v["openPgpPemFormatSecretKey"] = take(s);
            dkc_bytes sig; must(dkc_signing_key_sign(js.c_str(), msg, message.size(), &sig, &err), err, c.name);
            v["message"] = message; v["signatureHex"] = hex(sig);
        } else if (type == "SymmetricKey") {
            must(dkc_symmetric_key_derive(c.seed, c.recipe, &j, &err), err, c.name);
            std::string js = take(j); v["json"] = js; v["keyBytesHex"] = json::parse(js)["keyBytes"];
            must(dkc_symmetric_key_seal(js.c_str(), msg, message.size(), "", &s, &err), err, c.name);
            v["message"] = message; v["packagedSealedMessageJson"] = take(s);
        } else if (type == "UnsealingKey") {
            must(dkc_unsealing_key_derive(c.seed, c.recipe, &j, &err), err, c.name);
            std::string js = take(j); v["json"] = js;
            must(dkc_unsealing_key_sealing_key(js.c_str(), &s, &err), err, c.name); std::string sk = take(s); v["sealingKeyJson"] = sk;
            must(dkc_sealing_key_seal(sk.c_str(), msg, message.size(), "", &s, &err), err, c.name);
            v["message"] = message; v["packagedSealedMessageJson"] = take(s);
        }
        vectors.push_back(v);
    }
    out["vectors"] = vectors;
    printf("%s\n", out.dump(2).c_str());
    return 0;
}
