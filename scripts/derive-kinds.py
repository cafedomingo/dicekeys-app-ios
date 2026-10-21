#!/usr/bin/env python3
"""Derives every key kind independently of the Swift code, for Fixtures/kinds.json.

It reimplements docs/derivation.md: the seed's rotation, HKDF-SHA256 over the seed with
info = type || recipe, the recipe format, the encodings, the passphrase formatter and the
DiceKey id, reading only the EFF and BIP39 word lists from the Swift sources. The Swift tests
then check that the app derives the same values, so the fixture never comes from the code it
checks.

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
import hmac
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
# DiceKeys as typed, some in a non-canonical rotation, and the seeds the original DiceKeys C++
# derived from them: this script's rotation rule must reproduce those.
RECORDED_SEEDS = {
    "A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t": (
        "A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t"
    ),
    "F2lY4rC2bV6bX4rK1rD5lS4bG6bZ2lU4rA6tI5bB1lT3rP3lL6lH6lN2tE2rO2rW1tJ5lR1tM2b": (
        "F2lY4rC2bV6bX4rK1rD5lS4bG6bZ2lU4rA6tI5bB1lT3rP3lL6lH6lN2tE2rO2rW1tJ5lR1tM2b"
    ),
    "I5lW5tZ5tY2tD3rU1lX3bB4bA2bL2lC1lO1tP1tM2bS1lT1bR3lN2lJ3lE2rF3rG3rV5tH1lK3r": (
        "D3tL2bS1bE2tK3tY2lA2rM2rJ3bH1bZ5lB4rP1lN2bV5lW5lX3rO1lR3bG3tI5bU1bC1bT1rF3t"
    ),
    "N1rO6lX2tZ1lY5rA6rR1lE6bD2bM3bB4tP1tC6lU1tI3rK1tL6lW1rH1rJ2lF5lV4lT2rS4bG2l": (
        "F5tK1rB4rA6bN1bV4tL6tP1rR1tO6tT2bW1bC6tE6lX2rS4lH1bU1rD2lZ1tG2tJ2tI3bM3lY5b"
    ),
}
SEEDS = [
    "A1tB2rC3bD4lE5tF6rG1bH2lI3tJ4rK5bL6lM1tN2rO3bP4lR5tS6rT1bU2lV3tW4rX5bY6lZ1t",
    "F2lY4rC2bV6bX4rK1rD5lS4bG6bZ2lU4rA6tI5bB1lT3rP3lL6lH6lN2tE2rO2rW1tJ5lR1tM2b",
]

# The type is hashed in front of the recipe: what the derived bytes become.
TYPE_NAMES = {
    "ssh": "ed25519",
    "wireguard": "x25519",
    "age": "x25519",
    "passphrase": "passphrase",
    "wallet": "bip39",
}
MEMORABLE_WORD_LIST = "eff_large_wordlist"
LETTERS_DIGITS = "letters-digits"
LETTERS_DIGITS_SYMBOLS = "letters-digits-symbols"
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
# The recipe's JSON field names and values, as KeyRecipe.swift spells them.
KIND = "kind"
NAME = "name"
LENGTH = "length"
LIST = "list"
SEPARATOR = "separator"
UPPERCASE = "uppercase"
HYPHEN = "-"
DIGITS_SEPARATOR = "digits"
MAXIMUM_NAME_LENGTH = 64
# The DiceKey id is its own type with no recipe: info is just the type.
DICEKEY_ID_TYPE = "dicekey-id"
DICEKEY_ID_LENGTH = 16
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
    {"memorable": {"words": 6, "digitsAndUppercase": False}},
    {"memorable": {"words": 4, "digitsAndUppercase": True}},
    {"memorable": {"words": 10, "digitsAndUppercase": True}},
]


def swift_strings(path, name):
    text = path.read_text()
    body = text[text.index(f"let {name}") :]
    body = body[body.index("= [") + 3 : re.search(r"\n\s*\]", body).start()]
    return [json.loads(f'"{s}"') for s in re.findall(r'"((?:[^"\\]|\\.)*)"', body)]


MEMORABLE_WORDS = swift_strings(PACKAGE / "Sources" / "Derivation" / "WordLists+EFF.swift", "effLargeWords")
BIP39_WORDS = swift_strings(PACKAGE / "Sources" / "KeyFormats" / "BIP39+English.swift", "englishWords")


def hkdf_sha256(ikm, info, length, salt=bytes(32)):
    """RFC 5869 HKDF with HMAC-SHA256. No salt is the RFC's 32 zero bytes."""
    prk = hmac.new(salt, ikm, hashlib.sha256).digest()
    out, previous, counter = b"", b"", 1
    while len(out) < length:
        previous = hmac.new(prk, previous + info + bytes([counter]), hashlib.sha256).digest()
        out += previous
        counter += 1
    return out[:length]


def check_rfc5869():
    """RFC 5869 appendix A, test cases 1 and 3; 3 has no salt, as the derivation does."""
    okm = hkdf_sha256(bytes([0x0B] * 22), bytes.fromhex("f0f1f2f3f4f5f6f7f8f9"), 42, bytes(range(13)))
    expected = "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"
    assert okm.hex() == expected, "RFC 5869 test case 1"
    okm = hkdf_sha256(bytes([0x0B] * 22), b"", 42)
    expected = "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8"
    assert okm.hex() == expected, "RFC 5869 test case 3"


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
    fields = {KIND: kind, NAME: name}
    if "random" in (style or {}):
        r = style["random"]
        fields |= {LENGTH: r["length"], LIST: LETTERS_DIGITS_SYMBOLS if r["symbols"] else LETTERS_DIGITS}
    elif "memorable" in (style or {}):
        m = style["memorable"]
        separator = DIGITS_SEPARATOR if m["digitsAndUppercase"] else HYPHEN
        fields |= {LENGTH: m["words"], SEPARATOR: separator, LIST: MEMORABLE_WORD_LIST}
        if m["digitsAndUppercase"]:
            fields[UPPERCASE] = True
    return json.dumps(fields, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def blocks(secret, size):
    """(index, quotient) per 8-byte block."""
    return [divmod(int.from_bytes(secret[i : i + 8], "big"), size)[::-1] for i in range(0, len(secret) - 7, 8)]


def passphrase(seed, recipe, style):
    info = TYPE_NAMES["passphrase"].encode() + recipe.encode()
    if "random" in style:
        chars = CHARACTERS[LETTERS_DIGITS_SYMBOLS if style["random"]["symbols"] else LETTERS_DIGITS]
        length = style["random"]["length"]
        return "".join(chars[index] for index, _ in blocks(hkdf_sha256(seed.encode(), info, length * 8), len(chars)))
    count = style["memorable"]["words"]
    entries = blocks(hkdf_sha256(seed.encode(), info, count * 8), len(MEMORABLE_WORDS))
    words = [MEMORABLE_WORDS[index] for index, _ in entries]
    if not style["memorable"]["digitsAndUppercase"]:
        return HYPHEN.join(words)
    upper = entries[-1][1] % count
    words[upper] = words[upper].upper()
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
        case["publicKey"], case["fingerprint"], case["secret"] = ssh(hkdf_sha256(seed.encode(), info, 32), name)
    elif kind in ("wireguard", "age"):
        scalar = hkdf_sha256(seed.encode(), info, 32)
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
        case["secret"] = bip39(hkdf_sha256(seed.encode(), info, 32))
    return case


def canonical_seed(text):
    """The smallest of the four quarter turns' texts. A clockwise turn moves the die at row r,
    column c to row c, column 4 - r, and turns its top t -> r -> b -> l -> t."""
    faces = [text[i : i + 3] for i in range(0, 75, 3)]
    turns = []
    for _ in range(4):
        turns.append("".join(faces))
        faces = [faces[5 * (4 - c) + r] for r in range(5) for c in range(5)]
        faces = [f[:2] + "trbl"["trbl".index(f[2]) + 1 - 4] for f in faces]
    return min(turns)


def hkdf_vector(seed, type_name, recipe, length):
    """The construction alone, below any key format."""
    output = hkdf_sha256(seed.encode(), type_name.encode() + recipe.encode(), length)
    return {"seed": seed, "type": type_name, "recipe": recipe, "length": length, "output": output.hex()}


def dicekey_id(seed):
    """16 bytes as unpadded URL-safe base64."""
    secret = hkdf_sha256(seed.encode(), DICEKEY_ID_TYPE.encode(), DICEKEY_ID_LENGTH)
    return {"seed": seed, "id": base64.urlsafe_b64encode(secret).decode().rstrip("=")}


def cases():
    result = []
    for seed in SEEDS:
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
                entropy = hkdf_sha256(case["seed"].encode(), case["type"].encode() + case["recipe"].encode(), 32)
                assert reference.check(case["secret"]), case["name"]
                assert bytes(reference.to_entropy(case["secret"])) == entropy, case["name"]
    print("keys match", ", ".join(TOOLS), "and the BIP39 reference")


def main():
    check_rfc5869()
    seeds = [{"text": text, "seed": canonical_seed(text)} for text in RECORDED_SEEDS]
    assert all(entry["seed"] == RECORDED_SEEDS[entry["text"]] for entry in seeds), "the rotation rule"
    passphrase = recipe_text("passphrase", "nas", {"random": {"length": 24, "symbols": False}})
    fixture = {
        "origin": "scripts/derive-kinds.py",
        "seeds": seeds,
        "hkdf": [
            hkdf_vector(SEEDS[0], TYPE_NAMES["ssh"], recipe_text("ssh", "github", None), 32),
            hkdf_vector(SEEDS[0], TYPE_NAMES["passphrase"], passphrase, 24 * 8),
            hkdf_vector(SEEDS[1], DICEKEY_ID_TYPE, "", DICEKEY_ID_LENGTH),
        ],
        "diceKeyIds": [dicekey_id(seed) for seed in SEEDS],
        "cases": cases(),
    }
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
