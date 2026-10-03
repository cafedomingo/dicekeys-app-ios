# A root-key utility rather than a password manager

**Not decided**, and listed under Ideas in `BACKLOG.md`. It would remove most of the app and change how
it is used. As a password manager the app loses to a real one on every daily measure: no
AutoFill, no sync, and a box of dice to fetch first. What a DiceKey uniquely gives is a root
secret that lives offline and regenerates other secrets on demand. That suits secrets touched
rarely and costly to lose, so the app would be where those are rebuilt from, never where they
are used.

**What it would be for.** The owner's actual uses, and nothing else:

- an age identity for encrypting backups. [age](https://age-encryption.org) is a small
  file encryption tool and format, a modern stand-in for encrypting files with GPG: a key is
  one line of text, and a file is encrypted to its public half. It matters only if backups
  are encrypted with age itself; a tool that takes a passphrase, such as Hyper Backup, wants
  a Password recipe instead;
- SSH keys, for clients and for server hosts, where a derived host key lets a rebuilt server
  keep its identity so `known_hosts` never objects;
- WireGuard keys;
- the encryption passphrase for a Synology NAS;
- one password, the password manager's master password.

Per-site passwords are not on the list, and they are what most of the app is built around.

**Most of the derivation already exists.** Each use is a recipe of an existing type, so
nothing in `derivation.md` changes and the other DiceKeys apps can still reproduce every key:

| Use | Recipe type | Output | Today | Checked against |
|---|---|---|---|---|
| SSH, client or host | SigningKey | OpenSSH | exists | `ssh-keygen -y` |
| age | UnsealingKey | `AGE-SECRET-KEY-1…` and `age1…`, bech32 | new encoder | `age-keygen -y` |
| WireGuard | UnsealingKey | private and public key, base64 | new encoder | `wg pubkey` |
| NAS passphrase, master password | Password | as now | exists | |

age and WireGuard both use X25519 and clamp the scalar themselves, and an UnsealingKey's
`unsealingKeyBytes` is an X25519 scalar with `sealingKeyBytes` its public key, so both are
encodings of values already derived. The reference tools have to confirm that before anything
is relied on. Synology's limits on the passphrase have to be found before its recipe is made,
for the reason in the AutoFill item in `BACKLOG.md`: a recipe changed later is a different passphrase.

**Verify without revealing.** Re-derive and show only the public key or a fingerprint, and
compare it with the one recorded when the key was made. That is a recovery drill which shows
nothing secret, and a check on the scanner as well. It needs the public keys stored alongside
the recipes `DerivationRecipeStore` already keeps; they are no more secret than the recipes.

**Getting a key off the phone.** Exports are rare, once to provision and once after a
disaster, so they can be deliberate rather than convenient. In order of preference:

- the public key only, for `authorized_keys`, an age recipient or a WireGuard peer, so
  nothing secret moves;
- AirDrop or the share sheet, as a file, for an identity going to one's own Mac, at the cost
  of a file left in Downloads (the QR code sheet item in `BACKLOG.md` already asks whether this beats QR);
- the clipboard, as now, local only with a one-minute expiry, for passphrases;
- the app itself on the Mac, as in the iPad and Mac item in `BACKLOG.md`, deriving there rather than moving
  the key, on a more exposed machine;
- decrypting an age file on the phone, which moves nothing but means implementing age's file
  format, since the app seals and unseals nothing today. CryptoKit has every primitive.

Not a network transport or an SSH agent: large, and easy to get wrong.

**What it would remove.** The site templates and web-address recipes, which absorbs the
Simpler recipes item; the PGP and wallet templates, which no use above needs; per-site
password flows; and the AutoFill idea, which is the opposite bet, so choosing one rules out
the other. Raw JSON stays, as the way to reproduce a secret made elsewhere. Scanning, manual
entry, backup to Stickeys or a DiceKey kit, and the memory store with its expiry are the
root-key half of the app and stay.

**Before starting.** The rewritten scanner has not run on a device, and every output depends
on reading the key right. A phone is also a worse place for a root secret than an offline
machine; the answer is that the key is loaded rarely and briefly, which the expiry already
enforces. A first step that commits to nothing: the age and WireGuard encoders, the
public-key display and verify, with the removals decided after living with them.
