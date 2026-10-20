#!/usr/bin/env python3
"""Derives every key kind independently of the Swift code, for Fixtures/kinds.json.

It reimplements the construction from docs/derivation.md (keyed BLAKE2b HKDF over the seed,
info = type || recipe), the kind templates, encodings and password formatter from docs/derivation.md,
reading only the word lists from the Swift sources. The Swift tests then check
that the app derives the same values, so the fixture never comes from the code it checks.

  python3 scripts/derive-kinds.py           check the fixture against this implementation
  python3 scripts/derive-kinds.py --write   rewrite the fixture, only to add cases
  python3 scripts/derive-kinds.py --tools   also check every key with something other than this
                                            code: ssh-keygen, wg and age-keygen, which must be
                                            installed, and the BIP39 reference implementation

Two implementations can share a misreading of a format, so --tools has each format's own
tools read the keys back: they parse each secret and derive its public key and fingerprint,
and a recovery phrase must pass BIP39's checksum and decode to the entropy it came from.

Needs scripts/requirements.txt: `cryptography` for Ed25519 and X25519, and `mnemonic` for
--tools.
"""

import base64
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = ROOT / "Packages" / "Derivation"
FIXTURE = PACKAGE / "Tests" / "DerivationTests" / "Fixtures" / "kinds.json"
VECTORS = PACKAGE / "Tests" / "DerivationTests" / "Fixtures" / "vectors.json"

TYPE_NAMES = {
    "ssh": "SigningKey",
    "wireguard": "UnsealingKey",
    "age": "UnsealingKey",
    "passphrase": "Password",
    "wallet": "Secret",
}
MEMORABLE_WORD_LIST = "EFF_large_7776_words_9_chars_max_20160719"
LETTERS_DIGITS = "CHARS_57_letters_digits_20261002"
LETTERS_DIGITS_SYMBOLS = "CHARS_67_letters_digits_symbols_20261002"
CHARACTERS = {
    LETTERS_DIGITS: "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789",
    LETTERS_DIGITS_SYMBOLS: "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%&*-_?",
}
WHITE_SPACE = {
    0x09,
    0x0A,
    0x0B,
    0x0C,
    0x0D,
    0x20,
    0x85,
    0xA0,
    0x1680,
    *range(0x2000, 0x200B),
    0x2028,
    0x2029,
    0x202F,
    0x205F,
    0x3000,
}
# The recipe's JSON field names and values, as Recipe.swift spells them.
PURPOSE = "purpose"
LENGTH_IN_CHARS = "lengthInChars"
LENGTH_IN_WORDS = "lengthInWords"
SEPARATOR = "separator"
WORD_LIST = "wordList"
CAPITALIZE = "capitalize"
HYPHEN = "-"
DIGITS_SEPARATOR = "digits"
MAXIMUM_NAME_LENGTH = 64
ZERO_WIDTH_JOINER = "\u200d"
TOOLS = ("ssh-keygen", "wg", "age-keygen")

NAMES = [
    "github",
    "homelab host",
    "\u00dcn\u00efcode caf\u00e9",
    'quote " and \\ backslash',
    "  trimmed\u3000",
    "cafe\u0301",
    " \u0301x",
    "line\u2028separator",
    "\U0001f469\u200d\U0001f4bb laptop",
    "\U0001f9e8",
    "\U0001f1fa\U0001f1f8 & \U0001f44d\U0001f3fd",
    "\u0645\u0641\u062a\u0627\u062d \u0627\u0644\u062e\u0627\u062f\u0645",
    "\u65e5\u672c\u8a9e\u306e\u9375",
    "no\u00a0break / <tag> 'single'",
    "e\u0301" * 64,
    "x" * 64,
]
STYLES = [
    {"random": {"length": 24, "symbols": False}},
    {"random": {"length": 12, "symbols": True}},
    {"random": {"length": 64, "symbols": False}},
    {"memorable": {"words": 6, "digitAndCapital": False}},
    {"memorable": {"words": 4, "digitAndCapital": True}},
    {"memorable": {"words": 10, "digitAndCapital": True}},
]


def swift_strings(path, name):
    text = path.read_text()
    body = text[text.index(f"let {name}") :]
    body = body[body.index("= [") + 3 : re.search(r"\n\s*\]", body).start()]
    return [json.loads(f'"{s}"') for s in re.findall(r'"((?:[^"\\]|\\.)*)"', body)]


MEMORABLE_WORDS = swift_strings(PACKAGE / "Sources" / "Derivation" / "WordLists+EFF.swift", "effLargeWords")
BIP39_WORDS = swift_strings(PACKAGE / "Sources" / "KeyFormats" / "Wordlist.swift", "english")


def hkdf_blake2b(seed, info, length):
    prk = hashlib.blake2b(seed.encode(), key=bytes(32), digest_size=32).digest()
    out, previous, counter = b"", b"", 1
    while len(out) < length:
        previous = hashlib.blake2b(previous + info + bytes([counter]), key=prk, digest_size=32).digest()
        out += previous
        counter += 1
    return out[:length]


def normalized_name(name):
    scalars = [ord(c) for c in name]
    while scalars and scalars[0] in WHITE_SPACE:
        scalars.pop(0)
    while scalars and scalars[-1] in WHITE_SPACE:
        scalars.pop()
    result = unicodedata.normalize("NFC", "".join(map(chr, scalars)))
    assert result and len(result) <= MAXIMUM_NAME_LENGTH
    assert not any(unicodedata.category(c) in ("Cc", "Cn") for c in result)
    assert not any(unicodedata.category(c) == "Cf" and c != ZERO_WIDTH_JOINER for c in result)
    return result


def recipe_text(kind, name, style):
    """The recipe's fields in RFC 8785 (JCS) form, which for these flat ASCII-keyed objects is
    exactly Python's sorted, compact json.dumps."""
    fields = {PURPOSE: f"{kind}:{name}"}
    if "random" in (style or {}):
        r = style["random"]
        fields |= {LENGTH_IN_CHARS: r["length"], WORD_LIST: LETTERS_DIGITS_SYMBOLS if r["symbols"] else LETTERS_DIGITS}
    elif "memorable" in (style or {}):
        m = style["memorable"]
        separator = DIGITS_SEPARATOR if m["digitAndCapital"] else HYPHEN
        fields |= {LENGTH_IN_WORDS: m["words"], SEPARATOR: separator, WORD_LIST: MEMORABLE_WORD_LIST}
        if m["digitAndCapital"]:
            fields[CAPITALIZE] = True
    return json.dumps(fields, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def blocks(secret, size):
    """(index, quotient) per 8-byte block."""
    return [divmod(int.from_bytes(secret[i : i + 8], "big"), size)[::-1] for i in range(0, len(secret) - 7, 8)]


def passphrase(seed, recipe, style):
    info = b"Password" + recipe.encode()
    if "random" in style:
        chars = CHARACTERS[LETTERS_DIGITS_SYMBOLS if style["random"]["symbols"] else LETTERS_DIGITS]
        length = style["random"]["length"]
        return "".join(chars[index] for index, _ in blocks(hkdf_blake2b(seed, info, length * 8), len(chars)))
    count = style["memorable"]["words"]
    entries = blocks(hkdf_blake2b(seed, info, count * 8), len(MEMORABLE_WORDS))
    words = [MEMORABLE_WORDS[index] for index, _ in entries]
    if not style["memorable"]["digitAndCapital"]:
        return HYPHEN.join(words)
    capital = entries[-1][1] % count
    words[capital] = words[capital].upper()
    joined = words[0]
    for i in range(1, count):
        joined += str(entries[i - 1][1] % 10) + words[i]
    return joined


def ssh_string(data):
    return len(data).to_bytes(4, "big") + data


def pem(label, data):
    encoded = base64.b64encode(data).decode()
    lines = [encoded[i : i + 64] for i in range(0, len(encoded), 64)]
    return f"-----BEGIN {label}-----\n" + "\n".join(lines) + f"\n-----END {label}-----\n"


def ssh(seed_bytes, comment):
    public = Ed25519PrivateKey.from_private_bytes(seed_bytes).public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    blob = ssh_string(b"ssh-ed25519") + ssh_string(public)
    check = hashlib.sha256(public).digest()[:4]
    section = check + check + ssh_string(b"ssh-ed25519") + ssh_string(public) + ssh_string(seed_bytes + public)
    section += ssh_string(comment.encode())
    pad = 1
    while len(section) % 8:
        section += bytes([pad])
        pad += 1
    container = (
        b"openssh-key-v1\0"
        + ssh_string(b"none")
        + ssh_string(b"none")
        + ssh_string(b"")
        + (1).to_bytes(4, "big")
        + ssh_string(blob)
        + ssh_string(section)
    )
    line = f"ssh-ed25519 {base64.b64encode(blob).decode()} {comment}"
    fingerprint = "SHA256:" + base64.b64encode(hashlib.sha256(blob).digest()).decode().rstrip("=")
    return line, fingerprint, pem("OPENSSH PRIVATE KEY", container)


BECH32 = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"


def bech32(hrp, data):
    values, accumulator, bits = [], 0, 0
    for byte in data:
        accumulator, bits = accumulator << 8 | byte, bits + 8
        while bits >= 5:
            bits -= 5
            values.append(accumulator >> bits & 31)
    if bits:
        values.append(accumulator << (5 - bits) & 31)
    generator = [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]
    check = 1
    for value in [ord(c) >> 5 for c in hrp] + [0] + [ord(c) & 31 for c in hrp] + values + [0] * 6:
        top = check >> 25
        check = (check & 0x1FFFFFF) << 5 ^ value
        for i in range(5):
            if top >> i & 1:
                check ^= generator[i]
    check ^= 1
    return hrp + "1" + "".join(BECH32[v] for v in values + [check >> 5 * (5 - i) & 31 for i in range(6)])


def bip39(entropy):
    bits = int.from_bytes(entropy + hashlib.sha256(entropy).digest()[:1], "big")
    total = len(entropy) * 8 + len(entropy) // 4
    bits >>= 8 - len(entropy) // 4
    return " ".join(BIP39_WORDS[bits >> (11 * (total // 11 - 1 - i)) & 2047] for i in range(total // 11))


def derive(seed, kind, given, style):
    name = normalized_name(given)
    recipe = recipe_text(kind, name, style)
    case = {"seed": seed, "kind": kind, "input": given, "name": name, "recipe": recipe, "type": TYPE_NAMES[kind]}
    if style is not None:
        case["style"] = style
    info = TYPE_NAMES[kind].encode() + recipe.encode()
    if kind == "ssh":
        case["publicKey"], case["fingerprint"], case["secret"] = ssh(hkdf_blake2b(seed, info, 32), name)
    elif kind in ("wireguard", "age"):
        scalar = hashlib.sha512(hkdf_blake2b(seed, info, 32)).digest()[:32]
        public = X25519PrivateKey.from_private_bytes(scalar).public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
        if kind == "wireguard":
            case["publicKey"] = case["fingerprint"] = base64.b64encode(public).decode()
            case["secret"] = base64.b64encode(scalar).decode()
        else:
            case["publicKey"] = case["fingerprint"] = bech32("age", public)
            case["secret"] = bech32("age-secret-key-", scalar).upper()
    elif kind == "passphrase":
        case["secret"] = passphrase(seed, recipe, style)
    else:
        case["secret"] = bip39(hkdf_blake2b(seed, info, 32))
    return case


def cases():
    seeds = [key["seed"] for key in json.loads(VECTORS.read_text())["diceKeys"][:2]]
    result = []
    for seed in seeds:
        for kind in ("ssh", "wireguard", "age", "wallet"):
            for name in NAMES:
                result.append(derive(seed, kind, name, None))
        for style in STYLES:
            for name in NAMES[:3]:
                result.append(derive(seed, "passphrase", name, style))
    return result


def check_tools(fixture):
    missing = [tool for tool in TOOLS if not shutil.which(tool)]
    if missing:
        sys.exit("--tools needs " + ", ".join(missing))
    from mnemonic import Mnemonic

    reference = Mnemonic("english")
    with tempfile.TemporaryDirectory() as directory:
        for case in fixture:
            if case["kind"] == "ssh":
                path = Path(directory) / "key"
                path.write_text(case["secret"])
                path.chmod(0o600)
                derived = subprocess.run(["ssh-keygen", "-y", "-f", path], capture_output=True, text=True, check=True)
                assert derived.stdout.strip() == case["publicKey"], case["name"]
                public = Path(directory) / "key.pub"
                public.write_text(case["publicKey"] + "\n")
                listed = subprocess.run(["ssh-keygen", "-l", "-f", public], capture_output=True, text=True, check=True)
                assert listed.stdout.split()[1] == case["fingerprint"], case["name"]
            elif case["kind"] == "wireguard":
                derived = subprocess.run(
                    ["wg", "pubkey"], input=case["secret"], capture_output=True, text=True, check=True
                )
                assert derived.stdout.strip() == case["publicKey"], case["name"]
            elif case["kind"] == "age":
                path = Path(directory) / "identity"
                path.write_text(case["secret"] + "\n")
                derived = subprocess.run(["age-keygen", "-y", path], capture_output=True, text=True, check=True)
                assert derived.stdout.strip() == case["publicKey"], case["name"]
            elif case["kind"] == "wallet":
                entropy = hkdf_blake2b(case["seed"], case["type"].encode() + case["recipe"].encode(), 32)
                assert reference.check(case["secret"]), case["name"]
                assert bytes(reference.to_entropy(case["secret"])) == entropy, case["name"]
    print("keys match", ", ".join(TOOLS), "and the BIP39 reference")


def main():
    fixture = {"origin": "scripts/derive-kinds.py", "cases": cases()}
    if "--write" in sys.argv:
        FIXTURE.write_text(json.dumps(fixture, indent=1, ensure_ascii=False) + "\n")
        print(f"wrote {len(fixture['cases'])} cases")
    else:
        recorded = json.loads(FIXTURE.read_text())
        if recorded != fixture:
            sys.exit("kinds.json differs from this implementation")
        print(f"{len(fixture['cases'])} cases match")
    if "--tools" in sys.argv:
        check_tools(fixture["cases"])


if __name__ == "__main__":
    main()
