# DiceKey Vault design

DiceKey Vault turns a DiceKey (25 dice in a sealed box) into the few keys that are rarely used and expensive to lose: SSH client and host keys, WireGuard, age, a wallet's recovery phrase, and passphrases for anything that just calls for a password. It is where those keys get regenerated from. It is never where they get used. You open it a few times a year, so every screen has to make sense the first time you see it, with nothing to learn first.

"DiceKey Vault" is the working name. It names the DiceKey it works with, and About credits DiceKeys, LLC, who make the dice. The app uses none of their branding. It stores no secrets: the vault is the box of dice.

## Principles

- **The derivation is the product.** A DiceKey plus a kind plus a name always gives the same key. The interface's only job is to make those three inputs unambiguous and to show the output carefully.
- **The camera is the only setup.** No assembly walkthroughs, illustrations, tours or onboarding. Before the first DiceKey, home is one line and one button to the camera.
- **Public by default, secret on purpose.** A key's public half or fingerprint shows freely. The secret half stays concealed until a deliberate Reveal, and copying it is local only and clears after one minute.
- **The scan is the only check.** A scanned DiceKey is either one the app knows, with its name and keys, or a new one. An unexpected "New DiceKey" is how a misread die or the wrong box shows up, so it is stated plainly and paired with Scan again. Keys themselves carry no verify state: each derives the same way every time.
- **Making a key is looking it up.** A kind plus a name gives the key immediately, so New key shows the result live as you type, and Save only bookmarks it.
- **Capture on the best camera, derive on the safest machine.** The phone reads the DiceKey best. A desktop with a webcam (or Continuity Camera) is a fine place to derive and export. Both share the same screens.

## Platform: iOS 26 and macOS 26 and later, Liquid Glass

- It is a native SwiftUI app built from stock components, with one two-column `NavigationSplitView` for every size: home, with every DiceKey and its keys, then whichever of them is selected, a key opened from a DiceKey pushed over it. A phone shows the columns as a stack. The system draws the glass; this system only decides what goes on it.
- **There are two layers.** The navigation layer is glass: toolbars, the sidebar, sheets, and controls over the camera. The content layer is flat: rows, the DiceKey grid, keys and secrets. Never put glass on content, and never stack glass on glass.
- The tint is `accent-ink`. Use `.buttonStyle(.glassProminent)` only for the screen's one primary action, and `.glass` for the rest of the controls on the glass layer.
- On Mac the sidebar is a floating glass pane listing DiceKeys with their keys nested beneath. Toolbar actions sit in glass capsules at the top right. Scanning uses the Mac's camera or Continuity Camera and fills the detail pane.
- New key is a draft of the key's own detail, never a sheet: a pushed screen on iPhone and the detail pane on Mac. Keep sheets for confirmations, such as Forget.
- Over the camera, controls are system glass.

## App icon

The icon is a layered Icon Composer icon: a navy ground, with the DiceKey grid as the foreground layer. All 25 cells are filled in `accent`'s dark value, which holds up on the navy, each with its `on-accent` orientation bar, as a whole DiceKey. The navy and indigo nod to the original DiceKeys app without using its palette. It ships all four appearances: Default (navy), Dark (midnight ground), Clear (glass cells, light bars) and Tinted (monochrome, where the system supplies the hue). The files are in `docs/design/`: `app-icon-foreground.svg` is the grid layer for Icon Composer, and the other two are flattened Default and Dark renders. Don't add a letterform, a die in perspective or a key glyph.

## Content

- Use sentence case everywhere except `label` section labels, which are capitals. Address the user as "you" and never say "we".
- Verbs go first on buttons: "Scan DiceKey", "Type it in", "New key", "Reveal", "Copy", "Share", "Delete key", "Forget", "Forget DiceKey and its keys".
- Name the thing the user holds a "DiceKey". Name each derived output a "key", even a passphrase or recovery phrase. Name the free-text input the "name", never "label", "purpose" or "recipe".
- Status lines state facts: "Home box · 5 keys", "New DiceKey", "17 of 25 dice read", "Locks in 4:52", "Clears in 1 minute". No exclamation marks and no emoji.
- A DiceKey's default name is "DiceKey with M1 in center", using its center die. The user can rename it at any time, and the center die stays its avatar whatever the name.
- Never explain cryptography in the interface. Kinds are named by the tool they feed: SSH, WireGuard, age, Passphrase, Wallet.

## Color

- The neutrals are iOS's own: `ink` and `ink-muted` text, `bg-raised` rows and `line` separators come from stock components, so dark mode and Increase Contrast work without a custom palette. The one custom neutral is the ground, `bg`, washed with `bg-tint` at the top so grouped rows read as raised.
- `accent` (indigo) is the one hue. It marks the moment the machine reads something: a die just read, the selected die, and the primary action. Use it as a fill only, and put `on-accent` text on it. When the accent needs to be text or a mark, use `accent-ink`, which is also the app's tint; `accent-soft` is the ground of a key's kind icon.
- The primary action is `accent` with an `on-accent` label: the glass-prominent tint, in both themes. Allow one per screen.
- `danger` means only destruction. A misread die is told in words under the camera, in `ink-muted`. Success has no color of its own; a passphrase's strength bar is the one graded scale (`strength-weak` to `strength-strong`).
- The camera image sits on `camera` black, whatever the theme, with `camera-dim` over everything but the dice being read.
- A die is drawn as the real one looks: a light `die-face` with an `on-die` glyph, set in the dark `die-box`.

## Type

- Use system faces for everything except the dice: `sans` for interface text, and `mono` for secrets, public keys and fingerprints.
- `dice` (Inconsolata Bold) is the face printed on the physical dice, so a die on screen reads like the die in your hand. It is used only in the `die` style, wherever a DiceKey is drawn, and never for other text.
- Each screen has one `display` title, uses `headline` for row names, `subhead` for the line under a name, `caption` for status, and `label` for section labels. Every style but `die` is an iOS text style, so it follows Dynamic Type.
- `secret` and `key` text wraps anywhere and is never truncated with an ellipsis. Shorten a fingerprint by choosing a shorter format, never by cutting it.

## Layout and shape

- Screens are stock lists and forms on `bg`, so the system sets margins, row padding and the gaps between groups. The spacing tokens are for what the app lays out itself: `space-3` between a control and its caption and around the camera's controls, `space-2` inside a footer or between a phrase's words, `space-4` between the parts of a screen the app stacks itself, such as the grid and the keypad.
- Content is flat; depth belongs to the glass layer alone. A key's kind icon sits on an `accent-soft` tile with `radius-sm` corners, and the camera image is framed with `radius-md`. Buttons are capsules.
- A component's own proportions stay in the component: a die's corners, glyph and bar scale with its size, and the keypad's keys have their own gap.
- Touch targets are at least 44px. A die is 44px square in the grid.

## The DiceKey on screen

A DiceKey is drawn only as a 5×5 grid of dice in reading order, never as an illustration of the box in perspective. Each die shows the die's letter and digit in `die` type, rotated to the die's orientation, with a short bar under the glyph like the line printed on the real die, so upright, right, down and left read at a glance. Letters run A–Z without Q, and digits 1–6. The dice sit in a `die-box` ground, as in the real box. The grid starts concealed, every die a blank `die-face`, until Show dice. Typing selects a die with an `accent` outline.

## Motion

Motion is limited to state changes, and the system's own: lists animate rows in and out, and nothing else fades. A read die turns `accent` and stays so. An unlocked DiceKey's die on home is ringed in `accent-ink`. The DiceKey in use, the last opened or unlocked, keeps a full ring while the app is open; once another is opened or unlocked, or the app is left, the ring drains over the minute before it locks. Respect reduced motion: when it is on, the ring steps once a second.

## Iconography

Use SF Symbols on Apple platforms, at the text's weight, colored `ink` or `ink-muted`. Use `accent-ink` for a plain-button icon and `danger` for a destructive one. On other desktops, use the closest outline equivalent at a 1.5px stroke. The kinds are: SSH `terminal`, WireGuard `network`, age `lock.doc`, Passphrase `key`, Wallet `list.number`. The actions are `camera.viewfinder`, `keyboard`, `eye`, `doc.on.doc`, `square.and.arrow.up`, `printer`, `trash`. The app icon stands in for a logo. Where the app shows it, as on the cover the app switcher sees, `AppMark` draws its grid from the tokens, without the ground: `accent` dice with `on-accent` bars. Wherever a wordmark would go, set the name in `title` type.

## Tokens

In code a token keeps its name in lower camel case: the color sets in `DiceKeys/Resources/Colors.xcassets` are named as below, so `on-accent` is `Color.onAccent`, and spacing and radii are `CGFloat` constants such as `.space3` and `.radiusMd` in `DiceKeys/Shared/LayoutTokens.swift`. Change a token there and everything drawn with it follows. A token marked "system" is iOS's own and has no color set.

| Token | Light | Dark | Use |
|---|---|---|---|
| `bg` | `#f3f4f8` | `#0a0b10` | Ground behind lists and forms. |
| `bg-tint` | `#e4e4f6` | `#17173a` | Top of the ground, fading into `bg` by the middle of the screen. |
| `bg-raised` | system | system | List rows and sheets: the grouped background stock components draw. |
| `ink` | system | system | Primary text and icons: `.primary`. |
| `ink-muted` | system | system | Secondary text, captions and placeholders: `.secondary`. |
| `line` | system | system | Row separators, drawn by stock lists. |
| `accent` | `#3f3fb5` | `#5e5ce6` | The one hue. Fill only: the primary action, a just-read die, the selected die, the dice of the app mark. Text on it is always `on-accent`. Lighter in dark so it holds up on black. |
| `on-accent` | `#ffffff` | `#ffffff` | Text and icons on `accent` (5:1 or better). |
| `accent-ink` | `#3f3fb5` | `#8f8cff` | The app's tint: accent as text and marks, such as links, plain buttons, a kind's icon and the lock countdown. 5.6:1 or better on `bg` and `bg-raised` in both themes. |
| `accent-soft` | `#e4e4f7` | `#33317a` | Ground of a key's kind icon, under `accent-ink`. |
| `danger` | `#b81d16` | `#ff7b6b` | Destructive actions. Always with a word or an icon. 5.4:1 or better on `bg` and `bg-raised` in both themes. |
| `die-face` | `#fbfbf7` | `#e8eae2` | A die's face, and a concealed die. |
| `on-die` | `#121411` | `#121411` | A die's glyph and bar, and its faint shadow. |
| `die-box` | `#24244a` | `#16162e` | The ground the 25 dice sit in. |
| `camera` | `#000000` | `#000000` | Behind the live camera image, in every theme. |
| `camera-dim` | `rgba(0, 0, 0, 0.75)` | `rgba(0, 0, 0, 0.75)` | Darkens the camera image around the dice being read. |
| `strength-weak` | system red | system red | A passphrase's strength bar, weakest to strongest. |
| `strength-fair` | system orange | system orange | |
| `strength-good` | system yellow | system yellow | |
| `strength-strong` | system green | system green | |

| Style | iOS text style | Use |
|---|---|---|
| `display` | `.largeTitle` (navigation title) | One per screen: the screen's title. |
| `title` | `.title2`, semibold | A DiceKey's name at the top of its screen. |
| `headline` | `.headline` | A key's name in a row; the read count under the camera; button labels. |
| `body` | `.body` | Running text and field values. |
| `subhead` | `.subheadline` | The line under a name. |
| `caption` | `.footnote` | Status and helper lines, in `ink-muted`. |
| `label` | list section header | Section labels above groups, in capitals, `ink-muted`. |
| `die` | `dice`, sized to the die | A die's letter and digit, wherever a DiceKey is drawn: grid cells, the scan overlay and the keypad. It is used for nothing else. |
| `secret` | `.body`, monospaced | A revealed recovery phrase's words; a passphrase is `.title3` monospaced. Wraps anywhere; never truncated. |
| `key` | `.footnote`, monospaced | Public keys and fingerprints. Selectable, wraps anywhere. |

Families: `sans` is the system font, `mono` the system monospaced font, and `dice` Inconsolata Bold (`DiceKeys/fonts/Inconsolata-Bold.otf`).

| Spacing | Value | Use |
|---|---|---|
| `space-1` | 4px | Around the camera frame. |
| `space-2` | 8px | Inside a footer; between a recovery phrase's words. |
| `space-3` | 12px | Between a control and its caption; around and between the camera's controls. |
| `space-4` | 16px | Between the parts of a screen the app stacks itself. |
| `space-6` | 24px | Between examples in previews. |

| Radius | Value | Use |
|---|---|---|
| `radius-sm` | 9px | A key's kind icon tile. |
| `radius-md` | 16px | The camera frame. |

Sheets, rows and buttons take their corners from the system; buttons are capsules.

## In the app

- **Home** gives each DiceKey a section: its center die, name and status ("Locked · 4 keys", "Locks in 0:42"), then its keys, then New key while it is unlocked, so a key is one tap away. A DiceKey kept on this device unlocks from its row with Face ID. Scan DiceKey sits in the toolbar, since scanning is rare once DiceKeys are kept. Before the first DiceKey, home is the app mark, one line and Scan your DiceKey as the primary action.
- **The DiceKey grid** (`DiceKeyGrid`, `DieView`) is the only way a DiceKey is drawn. The center die alone (`DiceAvatar`) identifies a DiceKey in lists, whatever it is named.
- **A DiceKey's screen** opens with its avatar, name and status ("2 keys · unlocked", or "New DiceKey · no keys yet" with "Used this DiceKey before? A die may be misread" and Scan again), then the concealed grid, then its keys. A new DiceKey is also the normal first run, so the notice is plain, not an error.
- **Keeping a DiceKey on this device** is offered whenever a DiceKey that isn't kept is scanned or typed, in an alert as its screen opens: Keep on this device or Not now. Kept, it unlocks with Face ID or the passcode; not kept, it is read again each time it locks. The DiceKey's menu changes the choice later.
- **The camera** is framed on `camera` black, counts dice ("17 of 25 dice read") with one short hint, and hands straight to the DiceKey's screen when all 25 are read.
- **Typing a DiceKey** takes each die in three steps: its letter, its number, then which way is up, chosen from the die drawn four ways. Nothing defaults to upright, and a letter already on another die can't be typed: its key loses its fill and is struck through. The number pad fills the letters' space. Once every die is in, none is selected and Open DiceKey, the primary action, takes the keypad's place; tapping a die redoes it, and tapping it again puts it down. A half-typed DiceKey survives leaving the app for as long as an unlocked one does. A hardware keyboard types the same, with an arrow for where the top of the letter points.
- **Key rows** show the name and the kind, never a status or any part of a secret. Kinds aren't color-coded; spell them as their tools do ("age", "WireGuard").
- **New key** is a live draft in the detail column, never a sheet: kind, name, and the public key and fingerprint updating as you type. Save is the one primary action.
- **A key** opens with a centered header, not a table: its kind's icon tile, its name in `title` type in place of the navigation title, and its kind and date. It shows its public half in full, always, and its secret only after Reveal, never as dots or a length hint. Reveal is the primary action and sits where the secret will show, whether the DiceKey is unlocked or Face ID unlocks it first. Each value has the same two actions, Copy and Share, side by side under it; copying a secret is local only and says when it clears, and SSH and age identities share as the file their tool reads. A wallet's recovery phrase is the one exception: it is written down, never copied or shared. A key is deleted by swiping its row or from its screen, after a confirmation that says how to make it again.
- **Buttons**: one glass-prominent primary action per screen; Forget is destructive and always confirmed.
