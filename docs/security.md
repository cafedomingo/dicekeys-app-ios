# What is stored, and why it is safe

The DiceKey is the only secret. Everything else is either derived from it on demand or
public.

| What | Where | For how long |
|---|---|---|
| The DiceKey | Memory (`UnlockedDiceKeys`) | While it is the DiceKey in use (the last opened or unlocked) and the app is open; otherwise until 59 seconds after it stops being in use. After the app goes to the background, until it comes back 59 seconds or more later, or iOS ends it |
| The DiceKey, if "Keep on this device" | Keychain: `WhenUnlockedThisDeviceOnly`, `.userPresence`, not synchronizable | Until turned off or Forget |
| Derived keys | Memory: while New key shows its draft, which derives the whole key even when only the public half shows, and while revealed on screen | Dropped on Hide, leaving New key, lock, background, screen capture or screenshot |
| The catalog | SwiftData store, with iOS's default file protection (complete until the first unlock after a restart), so iOS can launch the app before then; it holds nothing secret | Until Forget |
| A copied secret | Pasteboard, local only (no Universal Clipboard) | 60 seconds, enforced by the system |
| A shared secret | Wherever it is sent from the share sheet, including the sheet's own Copy, which neither stays local nor expires | Up to the destination |

## The keychain copy

Reading it back requires Face ID, Touch ID or the passcode, enforced by the keychain itself.
It is never synced to iCloud Keychain, never in a backup another device can restore, and
unreadable while the device is locked. Forget deletes it before anything else, and stops if
it can't.

## The catalog, and iCloud

The catalog holds what is needed to derive each key again and nothing that unlocks one:

- per DiceKey: its id, its name, its center die (one face's letter, digit and turn) and the
  date it was first seen;
- per key: the DiceKey's id, the kind, the name, the passphrase style, the public key and the
  date.

With Sync with iCloud on (Settings; off by default) this goes to the user's private CloudKit
database, `iCloud.com.cafedomingo.dicekeys`, through SwiftData. That is safe because:

- **The id is one-way.** It is a 16-byte HKDF output from the DiceKey's 196 bits; nothing
  about the dice can be recovered from it, and checking a guess needs the guess.
- **Public keys are public.** They are made to be handed out, and a name says only what the
  key is for.
- **Nothing derives without the dice.** Kind, name and style are inputs, not secrets; without
  the physical DiceKey they open nothing. The center die is one face of 25, about 8 of the
  DiceKey's 196 bits, shown so the user can tell boxes apart.
- The DiceKey itself never syncs. Each device scans it, or keeps its own keychain copy.

What Apple could see is metadata: that a key named "wallet" exists, not the wallet. With
Advanced Data Protection the catalog is end-to-end encrypted. Turning sync off stops syncing
but leaves the iCloud copy; delete it under the device's iCloud storage settings.

A change to the switch applies at the next launch: the store opens once per launch, since two
CloudKit mirrors of one store file aren't supported. If the synced store won't open, the app
opens the same store without sync and Settings says why, rather than failing every launch.
Changes from other devices can arrive any time after the device's first unlock.

Two devices that each scan a DiceKey before they sync make a record each. One stands for the
DiceKey everywhere, the same one on every device: a renamed one over one still named for its
center die, then the oldest. Forget removes them all. Keys need no such step: they are told
apart by what they derive, so copies of one key show once.

## On screen

The app switcher shows a plain cover, put up synchronously when the scene backgrounds so the
snapshot never holds a secret. The DiceKey's grid starts concealed. A screenshot can't be
blocked; the app hides any revealed secret afterwards so it doesn't catch the next one. Typed
dice are dropped when the app comes back 59 seconds or more after leaving, as an unlocked
DiceKey is.

## Limits

Swift can't reliably zero memory, so a derived value may linger until reused. A device that
is compromised while a DiceKey is unlocked can read it; the lock delay keeps that window short.
A suspended app runs no timer, so a DiceKey unlocked when the app left stays in memory until
the app comes back and locks it, or until iOS ends the app.
