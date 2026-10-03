# A root-key utility rather than a password manager

**Not decided**, and listed under Ideas in `BACKLOG.md`. It would remove most of the app,
replace the derivation, and change how the app is used. As a password manager the app loses
to a real one on every daily measure: no AutoFill, no sync, and a box of dice to fetch first.
What a DiceKey uniquely gives is a root secret that lives offline and regenerates other
secrets on demand. That suits secrets touched rarely and costly to lose, so the app would be
where those are rebuilt from, never where they are used.

**What it would be for.** The owner's actual uses, and nothing else:

- SSH keys, for clients and for server hosts, where a derived host key lets a rebuilt server
  keep its identity so `known_hosts` never objects;
- WireGuard keys;
- the encryption passphrase for a Synology NAS;
- one password, the password manager's master password;
- possibly an age identity for encrypting backups. [age](https://age-encryption.org) is a
  small file encryption tool and format, a modern stand-in for encrypting files with GPG: a
  key is one line of text, and a file is encrypted to its public half. It matters only if
  backups are encrypted with age itself; a tool that takes a passphrase, such as Hyper
  Backup, wants a passphrase instead.

Per-site passwords are not on the list, and they are what most of the app is built around.

## A new derivation

Leaving the DiceKeys ecosystem is what makes the rest simple. The current derivation exists
to match the other DiceKeys apps byte for byte: a custom HKDF over BLAKE2b, JSON recipes
whose exact text is the salt, a canonical form that follows the reference rather than RFC
8785, five word lists and a dozen length options. None of that serves the uses above.

**The construction.** HKDF-SHA256 (RFC 5869, `HKDF<SHA256>` in CryptoKit) with:

- input key material: the seed string as today, the DiceKey rotated to its smallest form, so
  `DiceKeySeedTests` still proves every way of holding the key agrees;
- salt: one fixed, versioned domain string, the only place a version lives;
- info: the kind, the label and an index, each length-prefixed, so no two inputs encode
  alike and there is no text format to canonicalize;
- output: 32 bytes, always.

No stretching: a DiceKey carries about 196 bits of entropy, so a slow hash such as Argon2id
adds nothing, which also answers the Argon2id idea in `BACKLOG.md`.

**One output per kind, with no options.**

| Kind | From the 32 bytes | Checked against |
|---|---|---|
| SSH, client or host | Ed25519 seed, OpenSSH format | `ssh-keygen -y` |
| WireGuard | X25519 private key directly, base64 | `wg pubkey` |
| age | X25519 private key directly, bech32 | `age-keygen -y` |
| Passphrase | a fixed number of words from the BIP39 English list, 11 bits each | |

Nothing like `lengthInChars`, `lengthInWords` or a choice of word list. Twelve words is 132
bits. The one risk of a fixed format is a system that caps passphrase length, so Synology's
limits have to be known before the count is fixed, because the count can never change
afterwards.

**The label and the index.** The label says what the key is for, and the index replaces the
sequence number: rotating a key is the next index. Both are public, stored in the catalog
below, and shown on screen.

**Proving it without a reference.** Today's derivation is proved by vectors recorded from
the reference C++. A new one has no reference, so the spec has to be complete enough to
reimplement from, and CI should derive the vectors twice: once in Swift, once in a short
independent script (Python's standard library has HKDF's pieces and Ed25519 is one package
away). If the fork dies, the spec and that script are how the keys come back.

**What it costs.** The other DiceKeys apps can no longer reproduce anything, which today is
the fallback if this fork stops building. Goal 1 in `ARCHITECTURE.md` becomes "re-derive the
same secrets as the spec" rather than "as the reference". And every secret derived today
changes: anything already in use (an SSH key, a master password) has to be re-derived with the
current engine one last time and replaced, so the current engine stays until that is done and
is deleted after.

**What it deletes.** The BLAKE2 target, the BLAKE2b HKDF, JSON recipes and their
canonicalizer, `recipe-format.md`, `recipe-schema.json`, the password formatter's options,
all but one word list, OpenPGP, and in the end `vectors.json`. The open questions about
Argon2id, the seeding implementation and simpler recipes in `BACKLOG.md` all go with them.

## The app around it

**Verify without revealing.** Re-derive and show only the public key or a fingerprint, and
compare it with the one recorded when the key was made. That is a recovery drill which shows
nothing secret, and a check on the scanner as well.

**A catalog, not recipes.** Each key is a kind, a label, an index and, where there is one, a
public key. None of it is secret, so it can be stored freely, and the recipe builder becomes
a choice of kind and a text field.

**Getting a key off the phone.** Exports are rare, once to provision and once after a
disaster, so they can be deliberate rather than convenient. In order of preference:

- the public key only, for `authorized_keys`, a WireGuard peer or an age recipient, so
  nothing secret moves;
- AirDrop or the share sheet, as a file, for an identity going to one's own Mac, at the cost
  of a file left in Downloads (the QR code sheet item in `BACKLOG.md` already asks whether
  this beats QR);
- the clipboard, as now, local only with a one-minute expiry, for passphrases;
- the app itself on the Mac, as in the iPad and Mac item in `BACKLOG.md`, deriving there
  rather than moving the key, on a more exposed machine.

Not a network transport or an SSH agent: large, and easy to get wrong.

**What stays.** Scanning, manual entry, backup to Stickeys or a DiceKey kit, and the memory
store with its expiry are the root-key half of the app. The site templates, web-address and
raw JSON recipes, per-site password flows and the AutoFill idea go; AutoFill is the opposite
bet, so choosing one rules out the other.

**Before starting.** The rewritten scanner has not run on a device, and every output depends
on reading the key right. A phone is also a worse place for a root secret than an offline
machine; the answer is that the key is loaded rarely and briefly, which the expiry already
enforces. The order would be the spec and its two implementations first, then the catalog and
verify, then the removals, with the current engine last of all.
