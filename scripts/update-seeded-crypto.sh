#!/usr/bin/env bash
# Pulls upstream (or your fork's) changes to DiceKeys' seeded-crypto into the git subtree
# at Packages/DiceKeysCore/Vendor/seeded-crypto, merging three-way with any changes made
# here. Run from a clean working tree.
#
#   ./scripts/update-seeded-crypto.sh [git-url] [ref]
#   defaults: https://github.com/cafedomingo/seeded-crypto.git primary (your fork; pass
#   https://github.com/dicekeys/seeded-crypto.git to pull straight from upstream)
#
# The subtree was added with:
#   git subtree add --prefix=Packages/DiceKeysCore/Vendor/seeded-crypto <url> primary --squash
# Local deviations from upstream, all outside lib-seeded/: the extern/ submodule gitlinks and
# .gitmodules are removed, and extern/libsodium/ holds only the private argon2 header that
# recipe.cpp includes by relative path (force-added, since upstream's .gitignore has
# extern/**). Expect a merge conflict on those paths only if upstream bumps its libsodium
# submodule; keep ours.
#
# Afterwards: scripts/generate-golden-vectors.sh must produce no diff unless the derivation
# itself was deliberately changed, and CI's GoldenVectorTests must stay green.
set -euo pipefail
URL="${1:-https://github.com/cafedomingo/seeded-crypto.git}"
REF="${2:-primary}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
git subtree pull --prefix=Packages/DiceKeysCore/Vendor/seeded-crypto "$URL" "$REF" --squash \
  -m "Update seeded-crypto subtree from $URL $REF"
