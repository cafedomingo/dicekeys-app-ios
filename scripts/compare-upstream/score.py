#!/usr/bin/env python3
"""Scores the reads compare-upstream.sh collects as ScannerCorpusTests scores this repo's, and
prints Markdown tables.

A read is 75 characters, letter, digit and clockwise turns per face, "---" where no face was
read. Its faces are right or wrong in whichever of the four rotations of the expected key
reads best. A photo's name gives the key (75 characters, "---" for a die that cannot be seen);
a face read where the name has "---" counts as neither. Photos whose names are not a key's
(nokey-..., CausedCrash...) are not scored; the faces read from them are counted instead.

  python3 -I scripts/compare-upstream/score.py <corpus dir> <read-dicekey>/tests/test-lib-read-dicekey/img

The corpus dir holds repo-photos.tsv and repo-video.tsv, written by UpstreamCompareTests, and
upstream-photos.tsv, upstream-video-merged.tsv and upstream-video-single.tsv, written by
upstream-read.
"""

import csv
import statistics
import sys
from pathlib import Path

LETTERS = set("ABCDEFGHIJKLMNOPRSTUVWXYZ")
DIGITS = set("123456")
TURNS = {"t": 0, "r": 1, "b": 2, "l": 3, "0": 0, "1": 1, "2": 2, "3": 3}
TURN_LETTERS = "trbl"
SIZES = {
    "native": "native",
    "shorterSide1080": "short side 1080",
    "centeredSquare1080": "centered 1080 square",
    "shorterSide810": "short side 810",
}
FOLDERS = ["well-framed", "other"]
ORIGINS = ["upstream's", "owner's"]
# A photo is upstream's when this many leading characters of its name match one of upstream's, which
# is clear of the two names the corpus corrects.
ORIGIN_PREFIX = 15
FACES_IN_KEY = 25
UPSTREAM_COLUMNS = ["pgm", "ms", "finished", "faces", "errors"]
REPO = "this repo"
UPSTREAM = "upstream"
UPSTREAM_ERROR_FREE = "upstream, error-free faces only"
NOTHING = "---" * FACES_IN_KEY


def faces_of(name):
    """Corpus.faces(of:): 25 (letter, digit, turns) or None per face, or None for a name that is not a key's."""
    if len(name) != 3 * FACES_IN_KEY:
        return None
    faces = []
    for i in range(FACES_IN_KEY):
        triple = name[i * 3 : i * 3 + 3]
        if triple == "---":
            faces.append(None)
        elif triple[0] in LETTERS and triple[1] in DIGITS and triple[2] in TURNS:
            faces.append((triple[0], triple[1], TURNS[triple[2]]))
        else:
            return None
    return faces


def turned_clockwise(faces):
    turned = list(faces)
    for row in range(5):
        for column in range(5):
            face = faces[row * 5 + column]
            turned[column * 5 + 4 - row] = face and (face[0], face[1], (face[2] + 1) % 4)
    return turned


def score(read, expected):
    """Corpus.score: (right, wrong, [(expected, read) of each wrong face]) in the rotation with the most right."""
    best = (-1, 0, [])
    candidate = expected
    for _ in range(4):
        pairs = [(want, face) for face, want in zip(read, candidate) if face and want]
        right = sum(face == want for want, face in pairs)
        if right > best[0]:
            best = (right, len(pairs) - right, [(want, face) for want, face in pairs if want != face])
        candidate = turned_clockwise(candidate)
    return best


def face_text(face):
    return f"{face[0]}{face[1]}{TURN_LETTERS[face[2]]}"


def short_name(file):
    base = file.rsplit(".", 1)[0]
    return base if faces_of(base[:75]) is None else base[:9] + "…" + base[75:]


def read_tsv(path, columns=None):
    with open(path, newline="") as f:
        return list(csv.DictReader(f, delimiter="\t", fieldnames=columns))


def error_free(faces, errors):
    """Only the faces upstream read with errorSize() 0."""
    return "".join(faces[i * 3 : i * 3 + 3] if error == "0" else "---" for i, error in enumerate(errors.split(",")))


def table(header, rows):
    lines = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    return "\n".join(lines + ["| " + " | ".join(str(cell) for cell in row) + " |" for row in rows])


def right_wrong(totals):
    return f"{totals[0]}/{totals[1]}"


def main():
    corpus = Path(sys.argv[1])
    upstream_names = {path.name[:ORIGIN_PREFIX] for path in Path(sys.argv[2]).iterdir()}

    repo_rows = read_tsv(corpus / "repo-photos.tsv")
    upstream_rows = {row["pgm"]: row for row in read_tsv(corpus / "upstream-photos.tsv", UPSTREAM_COLUMNS)}
    keys = [(row["folder"], row["file"], row["size"]) for row in repo_rows]
    upstream_read = {key: upstream_rows[row["pgm"]] for key, row in zip(keys, repo_rows)}
    faces = {
        REPO: {key: row["faces"] for key, row in zip(keys, repo_rows)},
        UPSTREAM: {key: row["faces"] for key, row in upstream_read.items()},
        UPSTREAM_ERROR_FREE: {
            key: row["faces"] and error_free(row["faces"], row["errors"]) for key, row in upstream_read.items()
        },
    }
    finished = {key: row["finished"] == "1" for key, row in upstream_read.items()}

    photos = sorted({key[:2] for key in keys}, key=lambda photo: (FOLDERS.index(photo[0]), photo[1]))
    assert len({short_name(file) for _, file in photos}) == len(photos)
    expected = {photo: faces_of(photo[1].rsplit(".", 1)[0][:75]) for photo in photos}
    origin = {photo: ORIGINS[0] if photo[1][:ORIGIN_PREFIX] in upstream_names else ORIGINS[1] for photo in photos}
    visible = {photo: sum(face is not None for face in expected[photo] or []) for photo in photos}

    for key, row in zip(keys, repo_rows):
        want = expected[key[:2]]
        if want and score(faces_of(row["faces"]), want)[:2] != (int(row["right"]), int(row["wrong"])):
            raise SystemExit(f"score.py disagrees with Corpus.score on {row['file']} {row['size']}")

    def scored(scanner, photo, size):
        read = faces[scanner][(*photo, size)]
        if read is None:
            return None
        if expected[photo]:
            return score(faces_of(read), expected[photo])
        return sum(face is not None for face in faces_of(read))

    out = []

    def totals(group_of, groups, title):
        rows = []
        for group in groups:
            members = [photo for photo in photos if group_of(photo) == group and expected[photo]]
            for scanner in faces:
                cells = []
                for size in SIZES:
                    results = [scored(scanner, photo, size) for photo in members]
                    cells.append(right_wrong((sum(r[0] for r in results if r), sum(r[1] for r in results if r))))
                rows.append([f"{' '.join(group)}: {scanner}", len(members), sum(visible[p] for p in members), *cells])
            complete = [sum(finished[(*photo, size)] for photo in members) for size in SIZES]
            rows.append(
                [f"{' '.join(group)}: upstream complete keys (isFinished)", len(members), ""]
                + [f"{count} of {len(members)}" for count in complete]
            )
        header = ["", "photos", "faces visible", *SIZES.values()]
        out.append(f"### {title}\n\nFaces right/wrong.\n\n" + table(header, rows))

    totals(lambda photo: (photo[0],), [(folder,) for folder in FOLDERS], "Totals by folder")
    totals(
        lambda photo: (origin[photo], photo[0]),
        [(o, folder) for o in ORIGINS for folder in FOLDERS],
        "Totals by origin",
    )

    scanners = [REPO, UPSTREAM]
    columns = [f"{label}: {scanner}" for label in SIZES.values() for scanner in scanners]
    rows = [
        [short_name(photo[1])] + [scored(scanner, photo, size) for size in SIZES for scanner in scanners]
        for photo in photos
        if not expected[photo]
    ]
    out.append(
        "### Photos without an expected key\n\nFaces read. A `nokey-` photo must read nothing; "
        "CausedCrashOn2020-09-18, upstream's crash-regression input, shows a key but names none, so "
        "its faces are unscored.\n\n" + table(["photo", *columns], rows)
    )

    rows = []
    for photo in photos:
        if not expected[photo]:
            continue
        cells = []
        for size in SIZES:
            for scanner in scanners:
                result = scored(scanner, photo, size)
                cell = right_wrong(result) if result else "error"
                cells.append(cell + ("*" if scanner == UPSTREAM and finished[(*photo, size)] else ""))
        rows.append([short_name(photo[1]), photo[0], origin[photo], visible[photo], *cells])
    out.append(
        "### Per photo\n\nFaces right/wrong; `*` marks upstream's complete-key check passing "
        "(isFinished() after the one frame: every face error-free).\n\n"
        + table(["photo", "folder", "origin", "visible", *columns], rows)
    )

    rows = []
    for scanner in faces:
        for photo in photos:
            for size, label in SIZES.items():
                result = scored(scanner, photo, size) if expected[photo] else None
                if result and result[1]:
                    wrong = ", ".join(f"{face_text(want)} as {face_text(face)}" for want, face in result[2])
                    rows.append([scanner, short_name(photo[1]), label, result[1], wrong])
    out.append(
        "### Misreads\n\nEach wrong face as expected → read.\n\n"
        + (table(["scanner", "photo", "size", "wrong", "faces"], rows) if rows else "None.")
    )

    rows = []
    for scanner, rows_of in [(REPO, repo_rows), (UPSTREAM, list(upstream_read.values()))]:
        cells = []
        for size in SIZES:
            times = [float(row["ms"]) for key, row in zip(keys, rows_of) if key[2] == size and row["faces"]]
            cells.append(f"{statistics.median(times):.0f} / {max(times):.0f}")
        rows.append([scanner, *cells])
    out.append(
        "### Time per frame\n\nScanning only, after decoding and resizing.\n\n"
        + table(["scanner", *[f"{label}: median / max ms" for label in SIZES.values()]], rows)
    )

    frames = read_tsv(corpus / "repo-video.tsv")
    video_expected = faces_of(frames[0]["video"][:75])
    modes = ["merged", "single"]
    runs = [(REPO, mode, [frame[mode] for frame in frames], None) for mode in modes]
    for mode in modes:
        upstream_frames = read_tsv(corpus / f"upstream-video-{mode}.tsv", UPSTREAM_COLUMNS)
        runs.append(
            (
                UPSTREAM,
                mode,
                [row["faces"] or NOTHING for row in upstream_frames],
                [row["finished"] == "1" for row in upstream_frames],
            )
        )
    rows = []
    for scanner, mode, frame_reads, done in runs:
        scores = [score(faces_of(read), video_expected) for read in frame_reads]
        first_done = "" if done is None else next((i for i, d in enumerate(done) if d), "never")
        rows.append(
            [
                scanner,
                mode,
                len(frames),
                sum(s[1] > 0 for s in scores),
                max(s[1] for s in scores),
                sum(s[0] > 0 for s in scores),
                scores[-1][0],
                max(s[0] for s in scores),
                first_done,
            ]
        )
    out.append(
        "### Video, frame by frame\n\n`merged`: one scanner across the frames in order (upstream's "
        "DiceKeyImageProcessor merges each full read with the previous one); `single`: a fresh scanner per "
        "frame.\n\n"
        + table(
            [
                "scanner",
                "mode",
                "frames",
                "frames with a wrong face",
                "most wrong in a frame",
                "frames reading any face",
                "right after last frame",
                "most right in a frame",
                "first frame isFinished()",
            ],
            rows,
        )
    )
    print("\n\n".join(out))


if __name__ == "__main__":
    main()
