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
clang++ -std=c++17 -O1 -w -I"$LIB" -I"$PKG/SeededCryptoNative/include" -I"$PKG/CSodium/include" "$ROOT/scripts/generate-vectors.cpp" "$BUILD"/*.o -o "$BUILD/generate-vectors"
"$BUILD/generate-vectors" > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
echo "Wrote ${OUT#"$ROOT"/}"
