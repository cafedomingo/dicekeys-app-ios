#!/usr/bin/env bash
# Regenerates the golden derivation vectors from the vendored reference C++.
# Only run this if you deliberately changed lib-seeded or libsodium; a diff in the
# output means derived secrets changed, which is almost always a bug.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/Packages/DiceKeysCore/Sources"
BUILD="$ROOT/.build/golden"
mkdir -p "$BUILD"
CFLAGS="-O1 -w -DNATIVE_LITTLE_ENDIAN=1 -DHAVE_MADVISE -DHAVE_MMAP -DHAVE_MPROTECT -DHAVE_POSIX_MEMALIGN -DHAVE_WEAK_SYMBOLS -DCONFIGURED=1"
for f in $(find "$PKG/CSodium" -name '*.c'); do
  clang $CFLAGS -I"$PKG/CSodium/include" -I"$PKG/CSodium/include/sodium" -c "$f" -o "$BUILD/$(echo "$f" | tr '/' '_').o"
done
LIB="$ROOT/Packages/DiceKeysCore/Vendor/seeded-crypto/lib-seeded"
for f in $(find "$LIB" "$PKG/SeededCryptoNative" -name '*.cpp'); do
  clang++ -std=c++17 -O1 -w -I"$LIB" -I"$PKG/SeededCryptoNative/include" -I"$PKG/CSodium/include" -c "$f" -o "$BUILD/$(basename "$f").o"
done
clang++ -std=c++17 -O1 -w -I"$LIB" -I"$PKG/SeededCryptoNative/include" "$ROOT/scripts/generate-golden-vectors.cpp" "$BUILD"/*.o -o "$BUILD/generate-golden-vectors"
"$BUILD/generate-golden-vectors" > "$ROOT/Packages/DiceKeysCore/Tests/SeededCryptoTests/Fixtures/golden-vectors.json"
echo "Wrote Packages/DiceKeysCore/Tests/SeededCryptoTests/Fixtures/golden-vectors.json"
