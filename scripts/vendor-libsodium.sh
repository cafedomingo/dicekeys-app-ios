#!/usr/bin/env bash
# Re-vendors libsodium into Packages/DiceKeysCore/Sources/CSodium from a git ref.
#
#   ./scripts/vendor-libsodium.sh [git-url] [ref]
#   defaults: https://github.com/jedisct1/libsodium.git 1.0.22-RELEASE
#
# Copies src/libsodium, generates include/sodium/version.h with libsodium's own configure
# (the only generated header), drops the x86 assembly and autotools files, refreshes the
# private argon2 header that seeded-crypto includes, and rewrites VENDOR.md. Afterwards run
# scripts/generate-golden-vectors.sh and check that the fixture did not change.
set -euo pipefail
URL="${1:-https://github.com/jedisct1/libsodium.git}"
REF="${2:-1.0.22-RELEASE}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Packages/DiceKeysCore/Sources/CSodium"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone -q --depth 1 --branch "$REF" "$URL" "$WORK/libsodium"
SHA="$(git -C "$WORK/libsodium" rev-parse HEAD)"
( cd "$WORK/libsodium" && ( [ -x configure ] || ./autogen.sh -s ) && ./configure --disable-dependency-tracking -q >/dev/null )

rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$WORK/libsodium/src/libsodium/." "$DEST/"
cp "$WORK/libsodium/LICENSE" "$DEST/LICENSE"
rm -f "$DEST/include/sodium/version.h.in"
find "$DEST" \( -name 'Makefile*' -o -name '*.S' -o -name '*.s' -o -name '.dirstamp' -o -name '*.o' -o -name '*.lo' -o -name '*.la' -o -name '*.Plo' \) -delete
find "$DEST" -type d \( -name '.libs' -o -name '.deps' \) -prune -exec rm -rf {} +
find "$DEST" -type d -empty -delete
cat > "$DEST/include/module.modulemap" <<'MM'
module CSodium {
    umbrella header "sodium.h"
    export *
}
MM
# seeded-crypto's recipe.cpp includes this private header by relative path into what is,
# upstream, the libsodium submodule; keep the copy in the subtree current. The subtree's
# own .gitignore ignores extern/**, so the copy has to be force-added.
ARGON2="$ROOT/Packages/DiceKeysCore/Vendor/seeded-crypto/extern/libsodium/src/libsodium/crypto_pwhash/argon2/argon2.h"
cp "$DEST/crypto_pwhash/argon2/argon2.h" "$ARGON2"
git -C "$ROOT" add -f "$ARGON2"
cat > "$DEST/VENDOR.md" <<MD
Vendored from $URL at ref \`$REF\` (commit $SHA) by scripts/vendor-libsodium.sh. Only \`src/libsodium\` is copied; \`include/sodium/version.h\` was generated from \`version.h.in\` by \`./configure\`; the x86 \`.S\` assembly files were dropped. License: ISC (see LICENSE).

libsodium is an independent project by Frank Denis, not part of DiceKeys. It is compiled from source here rather than pulled from swift-sodium's prebuilt xcframework because DiceKeys' seeded-crypto calls \`argon2id_hash_raw\`, a non-exported libsodium function (it needs Argon2id with an arbitrary-length salt, which the public \`crypto_pwhash\` API does not allow).
MD
echo "Vendored libsodium $REF ($SHA) into $DEST"
