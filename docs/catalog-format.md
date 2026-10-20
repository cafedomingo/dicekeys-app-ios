# The catalog's formats

Paper outlives app versions: a list card or recovery sheet printed today has to import in
every later version of the app. So do exported files. Version 1 has three forms:

- **The file:** readable JSON, `{"v":1,"diceKeys":[…],"keys":[…]}`, from Settings ▸ Export.
- **The link:** `dicekeyvault://import?catalog=<base64url>`, on the list card's QR code. The same
  JSON, compact with sorted keys and without public keys.
- **The recovery code:** `DKV1R:<base64url>`, on the recovery sheet. The same JSON plus
  `"diceKey"`, the 25 faces in human-readable form. It is never a link, so the faces don't
  pass through iOS link handling.

A DiceKey is `{"id","name","centerFace"}`. A key is `{"diceKey","kind","name"}` with `"style"` for
a passphrase (`{"random":{"length","symbols"}}` or `{"memorable":{"words","digitAndCapital"}}`)
and, in the file only, `"publicKey"`, which is never imported. The values:

- `id` and a key's `diceKey`: the DiceKey's 16-byte id as unpadded URL-safe base64.
- `kind`: `ssh`, `wireguard`, `age`, `passphrase` or `wallet`.
- `name`: as `derivation.md` normalizes it (trimmed, NFC, 1 to 64 scalars); a DiceKey's name
  that fails those rules is replaced by its default.
- A face, in `centerFace` and the recovery code's `diceKey`: its letter (`A` to `Z` without
  `Q`), digit (`1` to `6`) and which way its top points (`t`, `r`, `b`, `l`), such as `M1t`.
  `diceKey` is the 25 faces in reading order, 75 characters.

The rule: only add optional fields, kinds and style shapes. Never rename, remove or
reinterpret one. An app reads each key on its own and leaves out, and counts, any it can't
make again (a kind or style it doesn't know, or a name its rules refuse), so a newer key
never costs the rest of the paper. Raise `v` only when an older app would otherwise get
something wrong; an app refuses a newer `v`.

`Tests/DiceKeysTests/Fixtures` holds v1 of each form, written once and never regenerated. A
failing fixture test means the change breaks paper already printed.
