// SeededCryptoNative: a plain-C ABI over the DiceKeys seeded-crypto C++ library.
//
// Why a C ABI and not Swift/C++ interop: lib-seeded reports failures with C++
// exceptions, which cannot cross into Swift. Every function here catches them and
// returns the message through `error_out`. No Objective-C is involved anywhere.
//
// Conventions
//  - Objects are passed around as their canonical JSON form (the same JSON the
//    library's `toJson()` produces and `fromJson()` accepts). Swift keeps that JSON
//    and decodes the fields it needs.
//  - Every function returns 1 on success and 0 on failure. On failure `*error_out`
//    holds a malloc'd UTF-8 message; free it with `dkc_free`.
//  - Every `char **` / `dkc_bytes *` output is owned by the caller and must be
//    released with `dkc_free` / `dkc_bytes_free`.

#ifndef SEEDED_CRYPTO_NATIVE_H
#define SEEDED_CRYPTO_NATIVE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct dkc_bytes {
    uint8_t *data;
    size_t length;
} dkc_bytes;

void dkc_free(void *ptr);
void dkc_bytes_free(dkc_bytes bytes);

/// Version string of the vendored libsodium, for diagnostics.
const char *dkc_sodium_version(void);

// MARK: Derivation from a seed string. Output is the object's canonical JSON.

int dkc_password_derive(const char *seed, const char *recipe, char **json_out, char **error_out);
int dkc_secret_derive(const char *seed, const char *recipe, char **json_out, char **error_out);
int dkc_symmetric_key_derive(const char *seed, const char *recipe, char **json_out, char **error_out);
int dkc_unsealing_key_derive(const char *seed, const char *recipe, char **json_out, char **error_out);
int dkc_signing_key_derive(const char *seed, const char *recipe, char **json_out, char **error_out);
int dkc_signature_verification_key_derive(const char *seed, const char *recipe, char **json_out, char **error_out);

// MARK: Parse + re-canonicalize JSON (validates the JSON the app was handed).

int dkc_password_from_json(const char *json, char **json_out, char **error_out);
int dkc_secret_from_json(const char *json, char **json_out, char **error_out);
int dkc_symmetric_key_from_json(const char *json, char **json_out, char **error_out);
int dkc_unsealing_key_from_json(const char *json, char **json_out, char **error_out);
int dkc_sealing_key_from_json(const char *json, char **json_out, char **error_out);
int dkc_signing_key_from_json(const char *json, char **json_out, char **error_out);
int dkc_signature_verification_key_from_json(const char *json, char **json_out, char **error_out);
int dkc_packaged_sealed_message_from_json(const char *json, char **json_out, char **error_out);

// MARK: Derived public halves and key formats.

int dkc_unsealing_key_sealing_key(const char *unsealing_key_json, char **json_out, char **error_out);
int dkc_signing_key_signature_verification_key(const char *signing_key_json, char **json_out, char **error_out);
int dkc_signing_key_open_ssh_public_key(const char *signing_key_json, char **out, char **error_out);
int dkc_signing_key_open_ssh_pem_private_key(const char *signing_key_json, const char *comment, char **out, char **error_out);
int dkc_signing_key_open_pgp_pem_secret_key(const char *signing_key_json, const char *user_id, uint32_t timestamp, char **out, char **error_out);
int dkc_signature_verification_key_open_ssh_public_key(const char *key_json, char **out, char **error_out);

// MARK: Signing and verification.

int dkc_signing_key_sign(const char *signing_key_json, const uint8_t *message, size_t message_length, dkc_bytes *signature_out, char **error_out);
int dkc_signature_verification_key_verify(const char *key_json, const uint8_t *message, size_t message_length, const uint8_t *signature, size_t signature_length, int *verified_out, char **error_out);

// MARK: Sealing and unsealing. `unsealing_instructions` may be NULL or "".
// Sealing returns the PackagedSealedMessage JSON; unsealing returns plaintext bytes.

int dkc_symmetric_key_seal(const char *key_json, const uint8_t *message, size_t message_length, const char *unsealing_instructions, char **packaged_json_out, char **error_out);
int dkc_symmetric_key_unseal(const char *key_json, const char *packaged_json, dkc_bytes *plaintext_out, char **error_out);
int dkc_symmetric_key_unseal_ciphertext(const char *key_json, const uint8_t *ciphertext, size_t ciphertext_length, const char *unsealing_instructions, dkc_bytes *plaintext_out, char **error_out);
int dkc_sealing_key_seal(const char *sealing_key_json, const uint8_t *message, size_t message_length, const char *unsealing_instructions, char **packaged_json_out, char **error_out);
int dkc_unsealing_key_unseal(const char *unsealing_key_json, const char *packaged_json, dkc_bytes *plaintext_out, char **error_out);
int dkc_unsealing_key_unseal_ciphertext(const char *unsealing_key_json, const uint8_t *ciphertext, size_t ciphertext_length, const char *unsealing_instructions, dkc_bytes *plaintext_out, char **error_out);

/// Unseal with only the seed: derives the key from the recipe embedded in the packaged message.
int dkc_seed_unseal_with_symmetric_key(const char *seed, const char *packaged_json, dkc_bytes *plaintext_out, char **error_out);
int dkc_seed_unseal_with_unsealing_key(const char *seed, const char *packaged_json, dkc_bytes *plaintext_out, char **error_out);

// MARK: Recipe helpers.

/// Returns the recipe with every optional parameter made explicit (what the library actually hashed).
int dkc_recipe_with_all_optional_parameters_specified(const char *recipe, char **out, char **error_out);
/// Derives the raw primary secret bytes for a recipe (what every other derivation is built on).
int dkc_recipe_derive_primary_secret(const char *seed, const char *recipe, dkc_bytes *out, char **error_out);

#ifdef __cplusplus
}
#endif

#endif /* SEEDED_CRYPTO_NATIVE_H */
