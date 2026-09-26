// C ABI over lib-seeded. See include/SeededCryptoNative.h for the contract.

#include "SeededCryptoNative.h"

#include <cstdlib>
#include <cstring>
#include <exception>
#include <string>
#include <vector>

#include "lib-seeded.hpp"

namespace {

char *dupString(const std::string &s) {
    char *out = static_cast<char *>(std::malloc(s.size() + 1));
    if (out == nullptr) { return nullptr; }
    std::memcpy(out, s.data(), s.size());
    out[s.size()] = '\0';
    return out;
}

dkc_bytes dupBytes(const unsigned char *data, size_t length) {
    dkc_bytes out{nullptr, 0};
    out.data = static_cast<uint8_t *>(std::malloc(length == 0 ? 1 : length));
    if (out.data == nullptr) { return out; }
    if (length > 0) { std::memcpy(out.data, data, length); }
    out.length = length;
    return out;
}

dkc_bytes dupBytes(const std::vector<unsigned char> &v) { return dupBytes(v.data(), v.size()); }
dkc_bytes dupBytes(const SodiumBuffer &b) { return dupBytes(b.data, b.length); }

std::string str(const char *s) { return s == nullptr ? std::string() : std::string(s); }

void setError(char **error_out, const char *message) {
    if (error_out != nullptr) { *error_out = dupString(message ? message : "Unknown error"); }
}

/// Runs `body`, converting any C++ exception into an error string and a 0 return.
template <typename F>
int guarded(char **error_out, F body) {
    try {
        body();
        return 1;
    } catch (const std::exception &e) {
        setError(error_out, e.what());
    } catch (...) {
        setError(error_out, "Unknown native exception");
    }
    return 0;
}

}  // namespace

extern "C" {

void dkc_free(void *ptr) { std::free(ptr); }
void dkc_bytes_free(dkc_bytes bytes) { std::free(bytes.data); }
const char *dkc_sodium_version(void) { return sodium_version_string(); }

// MARK: Derivation

#define DKC_DERIVE(fn, Type)                                                                     \
    int fn(const char *seed, const char *recipe, char **json_out, char **error_out) {          \
        return guarded(error_out, [&] { *json_out = dupString(Type::deriveFromSeed(str(seed), str(recipe)).toJson()); }); \
    }

DKC_DERIVE(dkc_password_derive, Password)
DKC_DERIVE(dkc_secret_derive, Secret)
DKC_DERIVE(dkc_symmetric_key_derive, SymmetricKey)
DKC_DERIVE(dkc_unsealing_key_derive, UnsealingKey)
DKC_DERIVE(dkc_signing_key_derive, SigningKey)

int dkc_signature_verification_key_derive(const char *seed, const char *recipe, char **json_out, char **error_out) {
    return guarded(error_out, [&] {
        *json_out = dupString(SigningKey::deriveFromSeed(str(seed), str(recipe)).getSignatureVerificationKey().toJson());
    });
}

// MARK: JSON round trips

#define DKC_FROM_JSON(fn, Type)                                                                  \
    int fn(const char *json, char **json_out, char **error_out) {                              \
        return guarded(error_out, [&] { *json_out = dupString(Type::fromJson(str(json)).toJson()); }); \
    }

DKC_FROM_JSON(dkc_password_from_json, Password)
DKC_FROM_JSON(dkc_secret_from_json, Secret)
DKC_FROM_JSON(dkc_symmetric_key_from_json, SymmetricKey)
DKC_FROM_JSON(dkc_unsealing_key_from_json, UnsealingKey)
DKC_FROM_JSON(dkc_sealing_key_from_json, SealingKey)
DKC_FROM_JSON(dkc_signing_key_from_json, SigningKey)
DKC_FROM_JSON(dkc_signature_verification_key_from_json, SignatureVerificationKey)
DKC_FROM_JSON(dkc_packaged_sealed_message_from_json, PackagedSealedMessage)

// MARK: Public halves and key formats

int dkc_unsealing_key_sealing_key(const char *unsealing_key_json, char **json_out, char **error_out) {
    return guarded(error_out, [&] {
        *json_out = dupString(UnsealingKey::fromJson(str(unsealing_key_json)).getSealingKey().toJson());
    });
}

int dkc_signing_key_signature_verification_key(const char *signing_key_json, char **json_out, char **error_out) {
    return guarded(error_out, [&] {
        *json_out = dupString(SigningKey::fromJson(str(signing_key_json)).getSignatureVerificationKey().toJson());
    });
}

int dkc_signing_key_open_ssh_public_key(const char *signing_key_json, char **out, char **error_out) {
    return guarded(error_out, [&] {
        *out = dupString(SigningKey::fromJson(str(signing_key_json)).toOpenSshPublicKey());
    });
}

int dkc_signing_key_open_ssh_pem_private_key(const char *signing_key_json, const char *comment, char **out, char **error_out) {
    return guarded(error_out, [&] {
        *out = dupString(SigningKey::fromJson(str(signing_key_json)).toOpenSshPemPrivateKey(str(comment)));
    });
}

int dkc_signing_key_open_pgp_pem_secret_key(const char *signing_key_json, const char *user_id, uint32_t timestamp, char **out, char **error_out) {
    return guarded(error_out, [&] {
        *out = dupString(SigningKey::fromJson(str(signing_key_json)).toOpenPgpPemFormatSecretKey(str(user_id), timestamp));
    });
}

int dkc_signature_verification_key_open_ssh_public_key(const char *key_json, char **out, char **error_out) {
    return guarded(error_out, [&] {
        *out = dupString(SignatureVerificationKey::fromJson(str(key_json)).toOpenSshPublicKey());
    });
}

// MARK: Signing

int dkc_signing_key_sign(const char *signing_key_json, const uint8_t *message, size_t message_length, dkc_bytes *signature_out, char **error_out) {
    return guarded(error_out, [&] {
        *signature_out = dupBytes(SigningKey::fromJson(str(signing_key_json)).generateSignature(message, message_length));
    });
}

int dkc_signature_verification_key_verify(const char *key_json, const uint8_t *message, size_t message_length, const uint8_t *signature, size_t signature_length, int *verified_out, char **error_out) {
    return guarded(error_out, [&] {
        const std::vector<unsigned char> sig(signature, signature + signature_length);
        *verified_out = SignatureVerificationKey::fromJson(str(key_json)).verify(message, message_length, sig) ? 1 : 0;
    });
}

// MARK: Sealing

int dkc_symmetric_key_seal(const char *key_json, const uint8_t *message, size_t message_length, const char *unsealing_instructions, char **packaged_json_out, char **error_out) {
    return guarded(error_out, [&] {
        *packaged_json_out = dupString(
            SymmetricKey::fromJson(str(key_json)).seal(message, message_length, str(unsealing_instructions)).toJson());
    });
}

int dkc_symmetric_key_unseal(const char *key_json, const char *packaged_json, dkc_bytes *plaintext_out, char **error_out) {
    return guarded(error_out, [&] {
        *plaintext_out = dupBytes(
            SymmetricKey::fromJson(str(key_json)).unseal(PackagedSealedMessage::fromJson(str(packaged_json))));
    });
}

int dkc_symmetric_key_unseal_ciphertext(const char *key_json, const uint8_t *ciphertext, size_t ciphertext_length, const char *unsealing_instructions, dkc_bytes *plaintext_out, char **error_out) {
    return guarded(error_out, [&] {
        *plaintext_out = dupBytes(
            SymmetricKey::fromJson(str(key_json)).unseal(ciphertext, ciphertext_length, str(unsealing_instructions)));
    });
}

int dkc_sealing_key_seal(const char *sealing_key_json, const uint8_t *message, size_t message_length, const char *unsealing_instructions, char **packaged_json_out, char **error_out) {
    return guarded(error_out, [&] {
        *packaged_json_out = dupString(
            SealingKey::fromJson(str(sealing_key_json)).seal(message, message_length, str(unsealing_instructions)).toJson());
    });
}

int dkc_unsealing_key_unseal(const char *unsealing_key_json, const char *packaged_json, dkc_bytes *plaintext_out, char **error_out) {
    return guarded(error_out, [&] {
        *plaintext_out = dupBytes(
            UnsealingKey::fromJson(str(unsealing_key_json)).unseal(PackagedSealedMessage::fromJson(str(packaged_json))));
    });
}

int dkc_unsealing_key_unseal_ciphertext(const char *unsealing_key_json, const uint8_t *ciphertext, size_t ciphertext_length, const char *unsealing_instructions, dkc_bytes *plaintext_out, char **error_out) {
    return guarded(error_out, [&] {
        *plaintext_out = dupBytes(
            UnsealingKey::fromJson(str(unsealing_key_json)).unseal(ciphertext, ciphertext_length, str(unsealing_instructions)));
    });
}

int dkc_seed_unseal_with_symmetric_key(const char *seed, const char *packaged_json, dkc_bytes *plaintext_out, char **error_out) {
    return guarded(error_out, [&] {
        *plaintext_out = dupBytes(SymmetricKey::unseal(PackagedSealedMessage::fromJson(str(packaged_json)), str(seed)));
    });
}

int dkc_seed_unseal_with_unsealing_key(const char *seed, const char *packaged_json, dkc_bytes *plaintext_out, char **error_out) {
    return guarded(error_out, [&] {
        *plaintext_out = dupBytes(UnsealingKey::unseal(PackagedSealedMessage::fromJson(str(packaged_json)), str(seed)));
    });
}

// MARK: Recipes

int dkc_recipe_with_all_optional_parameters_specified(const char *recipe, char **out, char **error_out) {
    return guarded(error_out, [&] {
        *out = dupString(Recipe(str(recipe)).recipeWithAllOptionalParametersSpecified());
    });
}

int dkc_recipe_derive_primary_secret(const char *seed, const char *recipe, dkc_bytes *out, char **error_out) {
    return guarded(error_out, [&] {
        *out = dupBytes(Recipe::derivePrimarySecret(str(seed), str(recipe)));
    });
}

}  // extern "C"
