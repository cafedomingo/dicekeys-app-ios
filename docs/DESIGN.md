# DiceKey Vault design

DiceKey Vault turns a DiceKey (25 dice in a sealed box) into the few keys that are rarely used and expensive to lose: SSH client and host keys, WireGuard, age, a wallet's recovery phrase, and passphrases for anything that just calls for a password. It is where those keys get regenerated from. It is never where they get used. You open it a few times a year, so every screen has to make sense the first time you see it, with nothing to learn first.

"DiceKey Vault" is the working name. It names the DiceKey it works with, and About credits DiceKeys, LLC, who make the dice. The app uses none of their branding. It stores no secrets: the vault is the box of dice.

## Principles

- **The derivation is the product.** A DiceKey plus a kind plus a name always gives the same key. The interface's only job is to make those three inputs unambiguous and to show the output carefully.
- **The camera is the only setup.** No assembly walkthroughs, illustrations, tours or onboarding. The first screen is Load, and Load is the camera.
- **Public by default, secret on purpose.** A key's public half or fingerprint shows freely. The secret half stays concealed until a deliberate Reveal, and copying it is local only and clears after one minute.
- **The scan is the only check.** A scanned DiceKey is either one the app knows, with its name and keys, or a new one. An unexpected "New DiceKey" is how a misread die or the wrong box shows up, so it is stated plainly and paired with Scan again. Keys themselves carry no verify state: each derives the same way every time.
- **Making a key is looking it up.** A kind plus a name gives the key immediately, so New key shows the result live as you type, and Save only bookmarks it.
- **Capture on the best camera, derive on the safest machine.** The phone reads the DiceKey best. A desktop with a webcam (or Continuity Camera) is a fine place to derive and export. Both share the same screens.

## Platform: iOS 26 and macOS 26 and later, Liquid Glass

- It is a native SwiftUI app on both platforms, built from stock components: `NavigationStack` and `TabView` on iPhone, and `NavigationSplitView` on Mac. The system draws the glass; this system only decides what goes on it.
- **There are two layers.** The navigation layer is glass: tab bar, toolbars, floating buttons, sheets, the Mac sidebar, and controls over the camera. The content layer is flat: rows, cards, the DiceKey grid, keys and secrets on `bg` and `bg-raised`. Never put glass on content, and never stack glass on glass.
- The tint is `accent`. Use `.buttonStyle(.glassProminent)` only for the screen's one primary action, and `.glass` for the rest of the controls on the glass layer.
- On iPhone the tab bar floats at the bottom with two tabs, DiceKey and Keys, and New key is a separate glass circle beside it. Toolbar buttons are glass circles holding a symbol, with no text.
- On Mac the sidebar is a floating glass pane listing DiceKeys with their keys nested beneath. Toolbar actions sit in glass capsules at the top right. Scanning uses the Mac's camera or Continuity Camera and fills the detail pane.
- New key is a draft of the key's own detail, never a sheet: a pushed screen on iPhone and the detail pane on Mac. Keep sheets for confirmations, such as Forget this DiceKey.
- Over the camera, controls are glass on `glass-on-camera` with `on-camera` text.

## App icon

The icon is a layered Icon Composer icon: a navy ground, with the DiceKey grid as the foreground layer. Eleven cells are read in `accent`, each with its orientation bar, and the rest are frosted glass. The navy and indigo nod to the original DiceKeys app without using its palette. It ships all four appearances: Default (navy), Dark (midnight ground), Clear (glass cells, indigo kept only on the bars) and Tinted (monochrome, where the system supplies the hue). The files are in `docs/design/`: `app-icon-foreground.svg` is the grid layer for Icon Composer, and the other two are flattened Default and Dark renders. Don't add a letterform, a die in perspective or a key glyph.

## Content

- Use sentence case everywhere except `label` section labels, which are capitals. Address the user as "you" and never say "we".
- Verbs go first on buttons: "Scan DiceKey", "Type it in", "New key", "Reveal", "Copy", "Share as file", "Forget this DiceKey".
- Name the thing the user holds a "DiceKey". Name each derived output a "key", even a passphrase or recovery phrase. Name the free-text input the "name", never "label", "purpose" or "recipe".
- Status lines state facts: "Home box · 5 keys", "New DiceKey", "17 of 25 dice read", "Locks in 4:52", "Clears in 1 minute". No exclamation marks and no emoji.
- A DiceKey's default name is "DiceKey with M1 in center", using its center die. The user can rename it at any time, and the center die stays its avatar whatever the name.
- Never explain cryptography in the interface. Kinds are named by the tool they feed: SSH, WireGuard, age, Passphrase, Wallet.

## Color

- The UI is mostly neutral: `bg` ground, `bg-raised` cards and fields, `fill` for die cells and tags, `ink` and `ink-muted` text, and `line` hairlines.
- `accent` (indigo) is the one hue. It marks the moment the machine reads something: the scan reticle, a die just read, and the primary action. Use it as a fill only, and put `on-accent` text on it. When the accent needs to be text or a mark, use `accent-ink`.
- Primary actions use `primary` and `on-primary`, which is the glass-prominent tint: indigo with a white label in both themes. Allow one per screen.
- `danger` means only destruction or a misread die. Success has no color of its own.
- The camera view is always `camera` black with `camera-dim` outside the reticle, whatever the theme, and its text is `on-camera`.
- The focus ring is a solid 2px `accent-ink` outline with a 2px offset. It holds 5.6:1 or better on every ground.

## Type

- Use system faces for everything except the dice: `sans` for interface text, and `mono` for secrets, public keys and fingerprints.
- `dice` (Inconsolata Bold) is the face printed on the physical dice, so a die on screen reads like the die in your hand. It is used only in the `die` style, wherever a DiceKey is drawn, and never for other text.
- Each screen has one `display` title, uses `headline` for row names, `subhead` for the line under a name, `caption` for status, and `label` for section labels.
- `secret` and `key` text wraps anywhere and is never truncated with an ellipsis. Shorten a fingerprint by choosing a shorter format, never by cutting it.

## Layout and shape

- On phone, use `space-4` side margins and put `space-6` between groups. On desktop, use a sidebar listing DiceKeys and keys, and a detail pane with `space-6` padding. There is no third column.
- Content is flat. Cards and groups are `bg-raised` with `radius-md` and a `line` hairline. Depth belongs to the glass layer alone.
- Buttons and segmented controls are capsules (`radius-full`). Die cells, tags and fields use `radius-sm`. Sheets and desktop panes use `radius-lg`.
- Touch targets are at least 44px. A die cell is 44px square on phone and 40px on desktop.

## The DiceKey on screen

A DiceKey is drawn only as a 5×5 grid of cells in reading order, never as an illustration of a box. Each cell shows the die's letter and digit in `die` type, rotated to the die's orientation, with a short bar under the glyph like the line printed on the real die, so upright, right, down and left read at a glance. Letters run A–Z without Q, and digits 1–6. When the user conceals the grid, every cell shows a blank `fill`. A comparison (a backup scanned against the original) rings each differing die in `danger` and says how many differ.

## Motion

Motion is limited to state changes. A die cell fades to `accent` and back over 300ms when it is read. Reveal crossfades the secret plate. Nothing loops except the scan reticle's corners while searching. Respect reduced motion: when it is on, the fade becomes a cut.

## Iconography

Use SF Symbols on Apple platforms, at the text's weight, colored `ink` or `ink-muted`. Use `accent-ink` for a plain-button icon and `danger` for a destructive one. On other desktops, use the closest outline equivalent at a 1.5px stroke. The kinds are: SSH `terminal`, WireGuard `network`, age `lock.doc`, Passphrase `key`, Wallet `list.number`. The actions are `camera.viewfinder`, `keyboard`, `eye`, `doc.on.doc`, `square.and.arrow.up`, `printer`. The app icon stands in for a logo. Wherever a wordmark would go, set the name in `title` type.

## Tokens

Colors come in light and dark. The `glass` tokens and `shadow-glass` only imitate Liquid Glass in previews; the app uses the system material.

| Token | Light | Dark | Use |
|---|---|---|---|
| `bg` | `#f4f4f1` | `#0b0c0b` | Window and screen ground. Lists, the key detail and the desktop sidebar sit on it. |
| `bg-raised` | `#ffffff` | `#171916` | Cards, list groups, sheets and text fields on `bg`. |
| `fill` | `#e9eae5` | `#22251f` | Die cells, kind tags, the concealed-secret plate and segmented-control tracks. Never under body text smaller than `subhead`. |
| `ink` | `#121411` | `#eff1ea` | Primary text and icons on `bg`, `bg-raised`, `fill` and `glass` (15:1 or better on the opaque grounds in both themes). |
| `ink-muted` | `#5a5f57` | `#9da397` | Secondary text: kind and date lines, captions, placeholders, unread die cells. Holds 5.4:1 or better on `bg`, `bg-raised` and `fill` in both themes. |
| `line` | `#d7d9d2` | `#2c2f29` | Hairline dividers between rows and around cards. Decorative only: never the sole boundary of a control. |
| `line-strong` | `#7f8479` | `#71766b` | Text field and checkbox borders, the outline of a selected die. 3:1 or better on `bg` and `bg-raised` in both themes. |
| `accent` | `#3f3fb5` | `#5e5ce6` | The one hue and the app's tint. Fill only: the primary action, the scan reticle, a just-read die, the tinted ✓ in sheets. Text on it is always `on-accent`. Lighter in dark so it holds up on black. |
| `on-accent` | `#ffffff` | `#ffffff` | Text and icons on `accent` (5:1 or better). |
| `accent-ink` | `#3f3fb5` | `#a9a6ff` | Accent as text and marks: links, plain buttons, the focus ring, the selected segment's mark. 5.6:1 or better on `bg`, `bg-raised` and `fill` in both themes. |
| `primary` | `{accent}` | `{accent}` | Primary action fill: the system's glass-prominent tint. One per screen. |
| `on-primary` | `{on-accent}` | `{on-accent}` | Primary action label on `primary` (5:1 or better). |
| `danger` | `#b81d16` | `#ff7b6b` | Destructive actions and misread dice: Forget this DiceKey, a die ring the scanner couldn't resolve. Always with a word or an icon. 5.4:1 or better on `bg`, `bg-raised` and `fill` in both themes. |
| `danger-soft` | `#fbe4e1` | `#3a1714` | Ground of a misread-die notice on the scan handoff; text on it is `danger` or `ink`. |
| `glass` | `rgba(255, 255, 255, 0.58)` | `rgba(44, 47, 41, 0.56)` | Liquid Glass tint in previews: tab bars, toolbars, floating buttons, sheets. In the app this is the system material (`.glassEffect()`), never a custom fill. Text on it is `ink`. |
| `glass-edge` | `rgba(255, 255, 255, 0.9)` | `rgba(255, 255, 255, 0.2)` | The specular rim along the top of a glass shape in previews. |
| `glass-on-camera` | `rgba(255, 255, 255, 0.16)` | `rgba(255, 255, 255, 0.16)` | Glass controls over the camera, in every theme. Text on it is `on-camera`. |
| `camera` | `#000000` | `#000000` | Behind the live camera image, in every theme. Text on it is `on-camera`. |
| `camera-dim` | `rgba(0, 0, 0, 0.6)` | `rgba(0, 0, 0, 0.6)` | Darkens the camera image outside the reticle. |
| `on-camera` | `#ffffff` | `#ffffff` | Status text and controls over `camera` and `camera-dim`. |

| Style | Family | Size / line | Weight | Use |
|---|---|---|---|---|
| `display` | sans | 34px / 40px | 700 | One per screen: the screen's title on phone, the detail pane's title on desktop. |
| `title` | sans | 22px / 28px | 600 | A key's name at the top of its detail; sheet titles. |
| `headline` | sans | 17px / 22px | 600 | A key's name in a row; button labels. |
| `body` | sans | 17px / 24px | 400 | Running text and field values. |
| `subhead` | sans | 15px / 20px | 400 | The line under a row's name; desktop body text. |
| `caption` | sans | 13px / 18px | 500 | Status and helper lines, in `ink-muted` unless they report a misread die. |
| `label` | sans | 12px / 16px | 600 | Section labels above groups, in capitals, `ink-muted`. |
| `die` | dice | 19px / 20px | 700 | A die's letter and digit, wherever a DiceKey is drawn: grid cells, the scan overlay and manual entry. Inconsolata Bold matches the face printed on the dice. It is used for nothing else. |
| `secret` | mono | 17px / 26px | 500 | A revealed passphrase or recovery phrase. Wraps anywhere; never truncated. |
| `key` | mono | 13px / 20px | 400 | Public keys and fingerprints. Selectable, wraps anywhere. |

Families: `sans` is the system font, `mono` the system monospaced font, and `dice` Inconsolata Bold (`DiceKeys/fonts/Inconsolata-Bold.otf`).

| Spacing | Value | Use |
|---|---|---|
| `space-1` | 4px | Gap between a die's glyph and its orientation bar; icon to label inside a tag. |
| `space-2` | 8px | Gap between die cells; between a row's name and its subhead line. |
| `space-3` | 12px | Row vertical padding; gap between a field and its caption. |
| `space-4` | 16px | Card and row horizontal padding; phone screen side margins. |
| `space-6` | 24px | Between groups on a screen; desktop pane padding. |
| `space-8` | 32px | Above a screen's display title; between the grid and the actions below it. |

| Radius | Value | Use |
|---|---|---|
| `radius-sm` | 8px | Die cells, tags, text fields. |
| `radius-md` | 14px | Cards, list groups, the secret plate, the camera frame. |
| `radius-lg` | 24px | Sheets and the desktop window's content panes. |
| `radius-full` | 999px | Buttons and segmented controls: always capsules. |

## Components

### DiceKeyGrid

The DiceKey drawn as a 5×5 grid of cells in reading order, each showing a die's letter and digit rotated to its orientation, with the orientation bar beneath. It is the only way a DiceKey appears on screen.

**Consumer provides:** 25 faces (letter A–Z without Q, digit 1–6, orientation upright/right/down/left) in reading order, and optionally a set of differing indexes and a concealed flag.

- Cells are `fill` with `die` type, inside a `bg-raised` card. Rotate the glyph, not the cell.
- A differing die is ringed in `danger` when a scanned backup disagrees with the loaded original, and the caption below says how many differ.
- Concealed blanks every cell. Use it whenever the DiceKey is unlocked but the grid isn't the subject, such as on the keys tab.
- Read (an `accent` cell) and unread (`ink-muted` glyph) are scan states, used by the overlay that follows a scan.
- Each cell's accessible name is the face in words, such as "A1 upright".
- Don't draw the box, the hinges or a die in perspective.

### DiceKeyHeader

The top of a DiceKey's screen right after a scan. It holds the one comparison the app makes: is this a DiceKey the app knows, or a new one?

**Consumer provides:** the DiceKey's name (or its default), its center die, whether it is known, the number of keys, and the time left before it locks.

- **Known:** the saved name in `display` with "Known · 5 keys · locks in 4:52" beneath, then straight on to the grid and keys.
- **New:** the default name "DiceKey with R2 in center" with "New DiceKey · no keys yet", plus the notice "Used this DiceKey before? A die may be misread." and a plain Scan again button. This is how a misread or the wrong box shows up, so never hide it. It isn't an error color, because a new DiceKey is also the normal first run.
- The avatar is the center die in `dice` type, rotated to its orientation, on `fill`. It identifies the DiceKey wherever it's listed (the home list, the Mac sidebar, the Keychain prompt), whatever the user has renamed it.
- Rename by tapping the name. The default name comes back if the field is cleared.

### ScanViewfinder

The live camera view that loads a DiceKey: the camera image, a square reticle, and each die drawn in `accent` over the image as soon as it's read.

**Consumer provides:** the camera stream (the phone's rear camera, a webcam, or Continuity Camera on a Mac), the faces read so far, and a status line.

- Always render it on `camera` black, with `camera-dim` outside the reticle and `on-camera` text, whatever the theme.
- The reticle corners are `accent`. They pulse while searching and hold still once the grid is found.
- The status line counts dice, as in "17 of 25 dice read", followed by one short hint. Never show a paragraph of instructions.
- When all 25 are read, hand off straight to the DiceKey screen. If a die is ambiguous, show the grid with that cell in `danger` and offer "Type it in".
- On desktop, the viewfinder fills the detail pane and the camera picker sits in its toolbar.

### KeyRow

One catalog entry in a DiceKey's list of keys: its name, its kind, and its public fingerprint (or the date it was made, for kinds with no public half).

**Consumer provides:** the name, the kind, the fingerprint or date, and the action that opens the key.

- The name is `headline`. The second line is `subhead` in `ink-muted`, holding the KindTag and then the fingerprint in `key` type.
- Rows carry no status. A key derives the same way every time, so there is nothing to report per row.
- Rows group in a `bg-raised` card, separated by `line`, ordered by name.
- A row never shows a secret, even partly.

### KindTag

A small neutral tag naming a key's kind with its icon: SSH, WireGuard, age, Passphrase or Wallet.

**Consumer provides:** the kind.

- Always use `fill` and `ink`. Kinds are not color-coded, because the name and icon already carry the meaning.
- Spell the kind as the tool spells it: "age" lower case, "WireGuard" in camel case.

### NewKeyDraft

Making a key, as a draft of the key's own detail: a kind and a name at the top, and the key itself below, derived live as you type. Save only adds the entry to the catalog. The key exists whether or not it's saved.

**Consumer provides:** the kinds, a derive function that runs on every edit, and the Save action.

- Open it as a pushed screen on iPhone and in the detail pane on Mac, never as a sheet. The output is the point, so it stays on screen.
- The kind is a segmented control. The name is a large `title`-sized field, kept exactly as typed (case included) and trimmed only at the ends.
- The public key and fingerprint update on every keystroke, and the caption says one changed letter is a different key. The private half stays Hidden until Reveal, as on any key.
- Save is the single primary action: a glass-prominent capsule at the bottom on iPhone, and in the toolbar beside Cancel on Mac. "Not saved" sits in the public key's footer until then.
- If the kind and name already exist for this DiceKey, the draft shows that saved key, and Save changes to Open.
- There are no options: no length, alphabet, word list or sequence number.

### SecretField

The secret half of a key: concealed until a deliberate Reveal, then shown whole in `secret` type with Copy and Hide.

**Consumer provides:** the kind's label, a way to derive the secret on demand, and the copy and share actions.

- Concealed is a `fill` plate reading "Hidden". Never show dots or a length hint.
- The primary action is Reveal. Once revealed, Copy becomes the main action (a neutral button, not primary) and Hide is plain.
- Copying is local only and expires after one minute. The caption says so every time.
- Files (SSH and age identities) get "Share as file" in place of Copy.
- Conceal again when the app goes to the background.

### PublicKey

A key's public half, shown in full in `key` type so it can be pasted into `authorized_keys`, a WireGuard peer or an age recipient.

**Consumer provides:** the public key line and its fingerprint.

- It is always visible, with no Reveal. Copying it never expires.
- Selecting it selects the whole value. It wraps anywhere and is never truncated.
- The SSH comment is the key's name, so the line says which key it is.

### Button

A capsule button with four variants: primary, neutral, plain and danger.

**Consumer provides:** the label (a verb first, in sentence case), an optional leading icon, and the action.

- Primary (`primary` with `on-primary`) is used at most once per screen, for the thing the screen is for.
- Neutral (`fill` with `ink`) is for secondary actions that matter, such as Copy or Type it in.
- Plain (`accent-ink` text) is for tertiary actions and toolbar items.
- Danger (`danger` text) is for Forget and Delete, and always asks for confirmation.
- Buttons are at least 44px tall and use `radius-full`.

## Screens

- **iPhone.** Load (the camera), a known DiceKey, a new DiceKey, the Keys tab, a key, and New key as a live draft.
- **Mac.** A floating glass sidebar of DiceKeys and their keys, with a key, New key, or the camera in the detail pane.
- **Not designed yet.** Type it in, Reveal for each kind, the paper copy and import, Forget this DiceKey, rename, and About.
