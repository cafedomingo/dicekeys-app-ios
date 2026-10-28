# The catalog's formats

Paper outlives app versions: a list card or recovery sheet printed today has to import in
every later version of the app, and so do exported files. There are three forms:

- **The file:** readable JSON, `{"v":1,"diceKeys":[…],"keys":[…]}`, from Settings ▸ Export.
  Version 1. It isn't size-bound, and being readable is its point.
- **The link:** `dicekeyvault://import?catalog=<payload>`, on the list card's QR code.
  Version 2.
- **The recovery code:** `DKVR:<payload>`, on the recovery sheet. Version 2. It is never a
  link, so the faces don't pass through iOS link handling.

The recovery prefix carries no version, so a later version's code is still recognized as
this app's and asks for an update.

## The file (v1)

A DiceKey is `{"id","name","centerFace"}`. A key is its recipe's own fields, exactly as
`derivation.md` defines them, plus `"diceKey"`, the id of the DiceKey it belongs to, and
`"publicKeys"`. The default keys come first, written like any other key, then the named
keys by name:

```
{"diceKey":"FDWCWOqOuLX6kRVI9K31_A","kind":"ssh","publicKeys":{"ed25519":"ssh-ed25519 AAAA…"}}
{"diceKey":"FDWCWOqOuLX6kRVI9K31_A","kind":"age","publicKeys":{"mlkem768x25519":"age1pq1…","x25519":"age1…"}}
{"diceKey":"FDWCWOqOuLX6kRVI9K31_A","kind":"ssh","name":"github","publicKeys":{"ed25519":"ssh-ed25519 AAAA… github"}}
{"diceKey":"FDWCWOqOuLX6kRVI9K31_A","kind":"passphrase","length":24,"list":"letters-digits","name":"nas"}
```

The values:

- `id` and a key's `diceKey`: the DiceKey's id as `derivation.md` defines it.
- A key's recipe fields: as `derivation.md` defines them. A default key's are its literal
  recipe's, `kind` alone. The JSON around them needn't be canonical; the app rebuilds the
  recipe's canonical text from the fields.
- `publicKeys`: each algorithm's public key, by its type (`derivation.md` lists a kind's
  types). It is for reading in the file, and never imported: a file could carry anyone's
  key, so a public key only ever comes from deriving it here. A key with no public half, a
  passphrase or a wallet, has none, and neither has a key whose public keys aren't recorded
  yet. A key whose `publicKeys` isn't a map of text is counted as unreadable.
- `name` of a DiceKey: as `derivation.md` normalizes a name; one that fails those rules is
  replaced by its default.
- `centerFace`: one face, such as `M1t`, as `derivation.md` writes faces.

## The link and the recovery code (v2)

Both carry one DiceKey and its keys as compact JSON with sorted keys and no whitespace, the
default keys first:

```
{"centerFace":"M1t","id":"FDWCWOqOuLX6kRVI9K31_A","keys":[{"kind":"ssh"},{"kind":"age"},{"kind":"ssh","name":"github"},{"kind":"passphrase","length":24,"list":"letters-digits","name":"nas"}],"name":"Home box","v":2}
```

- `id`, `name` and `centerFace` are the DiceKey's, with the values above.
- Each key is exactly its recipe's fields, with no `diceKey` (it belongs to `id`) and no
  `publicKeys`.
- The recovery code's JSON also has `"diceKey"`, the DiceKey's 75-character text. Restoring
  checks that those faces derive `id`.

`<payload>` is that JSON compressed with raw DEFLATE (RFC 1951) and written as base64url,
unpadded (RFC 4648 section 5). The decoder reads any key order and any valid DEFLATE stream.
Text that doesn't decode, inflate or parse is "not a catalog", and so is JSON that inflates
past 256 KiB (`PaperPayload.maximumUnpackedBytes`): the decoder stops there, since DEFLATE can
inflate about 1,000 to 1 and a link can come from anywhere.

What fits, measured with CoreImage for SSH keys with 12-character names that don't compress,
with the two default keys in the code too: the list card's code is a QR code (level M) held
to 119 modules wide, which is version 25 plus the generator's one-module margin. It holds 55
named keys; 56 need 123 modules. The recovery sheet's is an Aztec code at 33% error
correction, held to 188 modules wide but limited by the generator: it makes no code for 104
named keys, and 103 named keys take only 155 modules. Names that compress fit more; longer
names fit fewer. `PaperTests` pins floors of 40 named keys on the card and 80 on the sheet.

## Reading it

An app reads each key on its own, and leaves out and counts any it can't make again: a
field, kind or value it doesn't know, a name its rules refuse, or, in the file, a `diceKey`
that is neither in `diceKeys` nor already in the app. So a newer key never costs the rest of
the paper, and a field this version doesn't know is never read as a different recipe. A
recovery code's `id` must be the one its `diceKey` text derives. A file, link or code with
more than 1,000 DiceKeys and keys together is refused, and so is one whose `v` is newer than
the app's, with "update the app".

Default keys (`derivation.md`) are in every form, as their literal recipe's fields, so a
later app can make each again from the file or paper alone. Importing or restoring one the
catalog has adds nothing, as for any key. Importing or restoring a DiceKey the app doesn't
have records it, and recording a DiceKey adds its default keys. The printed lists, and the
counts shown before an import or restore, leave the defaults out: they show the keys the
person made.

The rule: only add optional fields, kinds and values, in the file and in v2. Never rename,
remove or reinterpret one. Raise `v` only when an older app would otherwise get something
wrong; an app refuses a newer `v`. Every later paper version keeps v2's envelope (the prefix
or link, raw DEFLATE, base64url, JSON with a top-level `v`), so an older app can say to
update.

`Tests/DiceKeyVaultTests/Fixtures` holds the file as v1 (`catalog-v1.json`) and the link and
recovery code as v2 (`catalog-link-v2.txt`, `recovery-v2.txt`). They are never regenerated: a
failing fixture test means the change breaks paper or files already written. The tests pin
what the paper fixtures decode to, not the encoder's bytes, since DEFLATE output may differ
between OS versions.
