The photos are named after the DiceKey they show: 75 characters, a letter, a digit and an
orientation per face (t/r/b/l, or 0-3 clockwise turns), with `---` for a die that cannot be
seen or was not checked, optionally followed by a `-note` or `_note` suffix. Photos named
`nokey-...` show no DiceKey and must read nothing; `CausedCrashOn2020-09-18.PNG` is a
crash-regression input with no expected value. The video in `../videos` is named the same way.

`well-framed/` holds the photos taken the way the scanning overlay asks, which must read;
`other/` holds the rest, which must only never be misread. Two photos in `other/` look well
framed but read little today, `U5bC4bE1l…` (nothing) and `Y6bS2rG4b…` (17 faces), and are the
first place to look for a scanner that reads more.

Where they come from:

- The owner's, of test keys, taken on an iPhone and stripped of everything but the picture:
  the `nokey-` photos, the video, and the photos of the keys `G5bS2rW5l…`, `---E2tM2tY2l…`,
  `---------------Y2bI6l…`, `S5rU1lX5r…`, `I5lZ3bX3t…`, `P5l---Y5r…` and `J2rC4rU1b…` (the
  key printed in the DiceKeys booklet). Their faces were read by eye at full resolution,
  except for `I5lZ3bX3t…`, `J2rC4rU1b…` and the video, whose expected faces are what the
  scanner read, checked by eye wherever the picture is sharp enough to tell.
- The rest come from https://github.com/dicekeys/read-dicekey (fork:
  https://github.com/cafedomingo/read-dicekey), `tests/test-lib-read-dicekey/img` at commit
  04400368ff3fa82f3eb19f06fb7bebc67a789603. One name is corrected from upstream: in
  `Y6bS2rG4b…`, X4, L3 and O1 are turned right in the photo, where upstream had them turned
  left.
