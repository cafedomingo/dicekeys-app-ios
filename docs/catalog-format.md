# The catalog's formats

Paper outlives app versions: a list card or recovery sheet printed today has to import in
every later version of the app, and so do exported files. Version 1 has three forms:

- **The file:** readable JSON, `{"v":1,"diceKeys":[…],"keys":[…]}`, from Settings ▸ Export.
- **The link:** `dicekeyvault://import?catalog=<base64url>`, on the list card's QR code: the
  same JSON, compact with sorted keys and without public keys.
- **The recovery code:** `DKV1R:<base64url>`, on the recovery sheet: the same JSON plus
  `"diceKey"`, the DiceKey's 75-character text. It is never a link, so the faces don't pass
  through iOS link handling.

base64url is unpadded (RFC 4648 section 5).

A DiceKey is `{"id","name","centerFace"}`. A key is its recipe's own fields, exactly as
`derivation.md` defines them, plus `"diceKey"`, the id of the DiceKey it belongs to, and, in
the file only, `"publicKey"`:

```
{"diceKey":"FDWCWOqOuLX6kRVI9K31_A","kind":"ssh","name":"github"}
{"diceKey":"FDWCWOqOuLX6kRVI9K31_A","kind":"passphrase","length":24,"list":"letters-digits","name":"nas"}
```

The values:

- `id` and a key's `diceKey`: the DiceKey's id as `derivation.md` defines it.
- A key's recipe fields: as `derivation.md` defines them. The JSON around them needn't be
  canonical; the app rebuilds the recipe's canonical text from the fields.
- `publicKey`: for reading in the file. It is never imported: a file could carry anyone's
  key, so a public key only ever comes from deriving it here.
- `name` of a DiceKey: as `derivation.md` normalizes a name; one that fails those rules is
  replaced by its default.
- `centerFace`: one face, such as `M1t`, as `derivation.md` writes faces.

An app reads each key on its own, and leaves out and counts any it can't make again: a
field, kind or value it doesn't know, a name its rules refuse, or a `diceKey` that is
neither in `diceKeys` nor already in the app. So a newer key never costs the rest of the
paper, and a field this version doesn't know is never read as a different recipe. A recovery
code must hold exactly one DiceKey, whose id is the one its text derives, and only that
DiceKey's keys. A file, link or code with more than 1,000 DiceKeys and keys together is
refused.

Default keys (`derivation.md`) are in none of the forms. Every DiceKey has them and they need
no name to come back, so the file, the link and the recovery code leave them out, and the
list card keeps its room for named keys. Importing or restoring a DiceKey the app doesn't
have records it, and recording a DiceKey adds its default keys.

The rule: only add optional fields, kinds and values. Never rename, remove or reinterpret
one. Raise `v` only when an older app would otherwise get something wrong; an app refuses a
newer `v`.

`Tests/DiceKeyVaultTests/Fixtures` holds v1 of each form. They are never regenerated: a failing
fixture test means the change breaks paper already printed.
