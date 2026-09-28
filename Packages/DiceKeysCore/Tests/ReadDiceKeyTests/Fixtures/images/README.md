The photos are named after the DiceKey they show: 75 characters, a letter, a digit and an
orientation per face (t/r/b/l, or 0-3 clockwise turns), with `---` for a die that cannot be
seen or was not checked, optionally followed by a `-note` or `_note` suffix. Photos named
`nokey-...` show no DiceKey and must read nothing; `CausedCrashOn2020-09-18.PNG` is a
crash-regression input with no expected value.

They come from https://github.com/dicekeys/read-dicekey (fork:
https://github.com/cafedomingo/read-dicekey), `tests/test-lib-read-dicekey/img` at commit
04400368ff3fa82f3eb19f06fb7bebc67a789603. One name is corrected from upstream: in
`Y6bS2rG4b…`, X4, L3 and O1 are turned right in the photo, where upstream had them turned
left.
