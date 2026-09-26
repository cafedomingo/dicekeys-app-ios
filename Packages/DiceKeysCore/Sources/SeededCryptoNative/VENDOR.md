`SeededCryptoNative.cpp` / `include/SeededCryptoNative.h` are ours: a C ABI so Swift can call
DiceKeys' seeded-crypto without Objective-C++ and without C++ exceptions crossing the
language boundary.

The library itself is the git subtree at `Packages/DiceKeysCore/Vendor/seeded-crypto`
(see `scripts/update-seeded-crypto.sh` for how it is tracked and updated).
