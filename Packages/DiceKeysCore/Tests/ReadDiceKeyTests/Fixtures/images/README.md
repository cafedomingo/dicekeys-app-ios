Photo corpus copied from https://github.com/dicekeys/read-dicekey (fork: https://github.com/cafedomingo/read-dicekey) `tests/test-lib-read-dicekey/img`
(commit 04400368ff3fa82f3eb19f06fb7bebc67a789603). Each file name is the DiceKey it shows,
75 characters with orientations or 50 without, optionally followed by `-note` / `_note`.
`CausedCrashOn2020-09-18.PNG` is a crash-regression input with no expected value.

`../reference-cpp-scanner.json` is the output of upstream's C++ scanner on these photos, captured
before the scanner was ported to Swift (commit 183d39d built it against OpenCV 4.6). The C++ and
its harness were removed in the port; regenerate from that commit if the fixture ever needs updating.
