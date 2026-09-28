# Vendored dependencies

The app has no external packages. Two libraries are vendored as source, and Dependabot cannot
see them, so updates are manual. After either update, `scripts/generate-golden-vectors.sh`
must produce no diff; `GoldenVectorTests` fails CI if derived output changes.

| Library | Packaged as | To update |
|---|---|---|
| libsodium 1.0.22 (jedisct1/libsodium, ISC) | Copy of `src/libsodium` in `Packages/DiceKeysCore/Sources/CSodium`; provenance in its `VENDOR.md`. | `scripts/vendor-libsodium.sh [url] [tag]` |
| seeded-crypto (dicekeys/seeded-crypto, MIT) | git subtree at `Packages/DiceKeysCore/Vendor/seeded-crypto`, pulled from the fork cafedomingo/seeded-crypto. `lib-seeded/` is unmodified. | `scripts/update-seeded-crypto.sh [url] [ref]` |

The scanner in `Sources/ReadDiceKey` is a Swift port of dicekeys/read-dicekey, not a copy;
upstream changes do not flow here. See `SCANNER-PORT-NOTES.md`.
