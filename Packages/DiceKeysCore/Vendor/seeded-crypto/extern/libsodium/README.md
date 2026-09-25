Upstream has its libsodium git submodule here. In this repository libsodium lives in
`Packages/DiceKeysCore/Sources/CSodium` (see its VENDOR.md); this directory only carries a
copy of the one private header `lib-seeded/recipe.cpp` includes by relative path
(`argon2.h`, refreshed by `scripts/vendor-libsodium.sh`), so the upstream source compiles
unmodified.
