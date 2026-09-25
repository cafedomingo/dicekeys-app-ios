#!/usr/bin/env python3
"""Generate Packages/DiceKeysCore/Sources/ReadDiceKey/OcrFontTables.swift from the
vendored C++ font data in
scripts/ocr-font-source/inconsolata-700.cpp.gz (upstream read-dicekey's generated glyph data,
kept gzipped next to this script since the C++ scanner was removed).

The C++ file holds three things the Swift scanner needs:
  * `letterPenalties` / `digitPenalties`: one byte per (row, column, character) of a
    70x53 glyph model; the high nibble is the penalty when the observed pixel is white,
    the low nibble when it is black (see simple-ocr.cpp, findClosestMatchingCharacter).
  * `CharacterOutlines::char_X`: the filled pixels of each glyph at 213x280, used only to
    draw the characters read into the overlay (write-face-characters.cpp).
  * the OcrFont header constants (Inconsolata700 at the end of the file).

A 3 MB Swift array literal would take the type checker minutes, so the tables are emitted
as base64 text (decoded once at runtime by GlyphTemplates) and the outlines are converted
to horizontal runs (y, xStart, xEnd inclusive) before encoding. Everything is verified to
round-trip before the file is written.

Usage: python3 scripts/generate-ocr-font-tables.py   (from the repository root)
"""

import base64
import gzip
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(
    ROOT, "scripts", "ocr-font-source", "inconsolata-700.cpp.gz")
OUTPUT = os.path.join(ROOT, "Packages", "DiceKeysCore", "Sources", "ReadDiceKey", "OcrFontTables.swift")

LETTERS = "ABCDEFGHIJKLMNOPRSTUVWXYZ"  # no Q, as in the DiceKey specification
DIGITS = "123456"
LINE_WIDTH = 96


def parse_penalties(src, name):
    m = re.search(r"const unsigned char " + name + r"\[\] = \{(.*?)\};", src, re.S)
    if not m:
        sys.exit("could not find " + name)
    values = [int(v) for v in re.findall(r"\d+", m.group(1))]
    if any(v > 255 for v in values):
        sys.exit(name + " has a value above 255")
    return bytes(values)


def parse_outline(src, char):
    m = re.search(r"const std::vector<UShortPoint> char_" + re.escape(char) + r" = \{(.*?)\};", src, re.S)
    if not m:
        sys.exit("could not find outline for " + char)
    return [(int(x), int(y)) for x, y in re.findall(r"\{\s*(\d+)\s*,\s*(\d+)\s*\}", m.group(1))]


def parse_font_constant(src, comment):
    m = re.search(r"([0-9.]+)f?,\s*//\s*" + re.escape(comment), src)
    if not m:
        sys.exit("could not find font constant " + comment)
    return m.group(1)


def points_to_runs(points):
    """Turns a set of pixels into (y, xStart, xEnd) runs, sorted by y then x."""
    unique = sorted(set(points), key=lambda p: (p[1], p[0]))
    runs = []
    for x, y in unique:
        if runs and runs[-1][0] == y and runs[-1][2] + 1 == x:
            runs[-1][2] = x
        else:
            runs.append([y, x, x])
    return [tuple(r) for r in runs]


def runs_to_points(runs):
    points = []
    for y, x0, x1 in runs:
        points.extend((x, y) for x in range(x0, x1 + 1))
    return points


def encode_runs(runs):
    if any(v > 0xFFFF for r in runs for v in r):
        sys.exit("run coordinate does not fit in UInt16")
    return b"".join(struct.pack("<HHH", y, x0, x1) for y, x0, x1 in runs)


def base64_literal(data, indent):
    text = base64.b64encode(data).decode("ascii")
    lines = [text[i:i + LINE_WIDTH] for i in range(0, len(text), LINE_WIDTH)]
    pad = " " * indent
    return pad + '"""\n' + "".join(pad + line + "\n" for line in lines) + pad + '"""'


def main():
    with gzip.open(SOURCE, "rt") as f:
        src = f.read()

    ocr_w = int(parse_font_constant(src, "ocrCharWidthInPixels"))
    ocr_h = int(parse_font_constant(src, "ocrCharHeightInPixels"))
    outline_w = int(parse_font_constant(src, "outlineCharWidthInPixel"))
    outline_h = int(parse_font_constant(src, "outlineCharHeightInPixels"))
    char_w_over_font = parse_font_constant(src, "charWidthOverFontSize")
    char_h_over_font = parse_font_constant(src, "charHeightOverFontSize")
    baseline = parse_font_constant(src, "fontBaselineFraction")

    letter_penalties = parse_penalties(src, "letterPenalties")
    digit_penalties = parse_penalties(src, "digitPenalties")
    if len(letter_penalties) != ocr_w * ocr_h * len(LETTERS):
        sys.exit("letterPenalties has %d bytes, expected %d" % (len(letter_penalties), ocr_w * ocr_h * len(LETTERS)))
    if len(digit_penalties) != ocr_w * ocr_h * len(DIGITS):
        sys.exit("digitPenalties has %d bytes, expected %d" % (len(digit_penalties), ocr_w * ocr_h * len(DIGITS)))

    # Check the alphabets in the C++ are the ones we assume, in the same order.
    letters_in_cpp = re.findall(r"//\s*'([A-Z])'\s*\{\s*'([A-Z])',\s*CharacterOutlines::char_([A-Z])", src)
    digits_in_cpp = re.findall(r"//\s*'([1-6])'\s*\{\s*'([1-6])',\s*CharacterOutlines::char_([1-6])", src)
    if "".join(a for a, _, _ in letters_in_cpp) != LETTERS or any(a != b or a != c for a, b, c in letters_in_cpp):
        sys.exit("letter alphabet in the C++ differs from " + LETTERS)
    if "".join(a for a, _, _ in digits_in_cpp) != DIGITS or any(a != b or a != c for a, b, c in digits_in_cpp):
        sys.exit("digit alphabet in the C++ differs from " + DIGITS)

    outlines = {}
    for ch in LETTERS + DIGITS:
        points = parse_outline(src, ch)
        if not points:
            sys.exit("empty outline for " + ch)
        if any(x >= outline_w or y >= outline_h for x, y in points):
            sys.exit("outline point out of range for " + ch)
        runs = points_to_runs(points)
        if sorted(set(points)) != sorted(set(runs_to_points(runs))):
            sys.exit("run-length encoding does not round-trip for " + ch)
        outlines[ch] = encode_runs(runs)

    out = []
    out.append("//")
    out.append("//  OcrFontTables.swift")
    out.append("//  ReadDiceKey")
    out.append("//")
    out.append("//  GENERATED by scripts/generate-ocr-font-tables.py from")
    out.append("//  scripts/ocr-font-source/inconsolata-700.cpp.gz (upstream read-dicekey glyph data).")
    out.append("//  Do not edit by hand; re-run the script instead.")
    out.append("//")
    out.append("//  The glyph model of the Inconsolata Bold characters printed on DiceKey faces, in the")
    out.append("//  form simple-ocr.cpp consumes: for every (row, column, character) of a 70x53 raster,")
    out.append("//  one penalty byte whose high nibble applies when the observed pixel is white and")
    out.append("//  whose low nibble applies when it is black. The outlines are the filled pixels of each")
    out.append("//  glyph at 213x280, stored as (y, xStart, xEnd) UInt16 runs; the overlay draws them.")
    out.append("//  Tables are base64 so the file stays small for the Swift type checker.")
    out.append("//")
    out.append("")
    out.append("enum InconsolataOCRFontData {")
    out.append("    static let charWidthOverFontSize: Float = %s" % char_w_over_font)
    out.append("    static let charHeightOverFontSize: Float = %s" % char_h_over_font)
    out.append("    static let fontBaselineFraction: Float = %s" % baseline)
    out.append("    static let ocrCharWidthInPixels = %d" % ocr_w)
    out.append("    static let ocrCharHeightInPixels = %d" % ocr_h)
    out.append("    static let outlineCharWidthInPixels = %d" % outline_w)
    out.append("    static let outlineCharHeightInPixels = %d" % outline_h)
    out.append("")
    out.append("    /// The letter alphabet, in table order (no Q).")
    out.append('    static let letterCharacters = "%s"' % LETTERS)
    out.append("    /// The digit alphabet, in table order.")
    out.append('    static let digitCharacters = "%s"' % DIGITS)
    out.append("")
    out.append("    /// %d bytes: [row 0..<%d][column 0..<%d][letter index 0..<%d]." % (len(letter_penalties), ocr_h, ocr_w, len(LETTERS)))
    out.append("    static let letterPenaltiesBase64 =")
    out.append(base64_literal(letter_penalties, 8))
    out.append("")
    out.append("    /// %d bytes: [row 0..<%d][column 0..<%d][digit index 0..<%d]." % (len(digit_penalties), ocr_h, ocr_w, len(DIGITS)))
    out.append("    static let digitPenaltiesBase64 =")
    out.append(base64_literal(digit_penalties, 8))
    out.append("")
    out.append("    /// Filled-pixel runs of each glyph, (y, xStart, xEnd inclusive) as little-endian UInt16 triples;")
    out.append("    /// one entry per character of `letterCharacters` followed by `digitCharacters`.")
    out.append("    static let outlineRunsBase64: [String] = [")
    for ch in LETTERS + DIGITS:
        out.append("        // '%s'" % ch)
        out.append(base64_literal(outlines[ch], 8) + ",")
    out.append("    ]")
    out.append("}")
    out.append("")

    with open(OUTPUT, "w") as f:
        f.write("\n".join(out))
    print("wrote %s (%d letter penalty bytes, %d digit penalty bytes, %d glyph outlines)" % (
        os.path.relpath(OUTPUT, ROOT), len(letter_penalties), len(digit_penalties), len(outlines)))


if __name__ == "__main__":
    main()
