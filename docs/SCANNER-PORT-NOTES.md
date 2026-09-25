# Scanner port notes: lib-read-dicekey in pure Swift

`Packages/DiceKeysCore/Sources/ReadDiceKey/` now implements the DiceKey scanning algorithm
natively: no OpenCV, no C++, no Objective-C, no third-party code, only Foundation. The
vendored C++ (`Sources/ReadDiceKeyNative/`, upstream `dicekeys/read-dicekey` at
`04400368`) stays in the tree as the reference until the corpus test has passed on a Mac;
the `ReadDiceKey` target no longer depends on it.

The public API of `DiceKeyScanner` is unchanged (`process(rgba:width:height:)`,
`readResultJSON`, `isFinished`, `renderOverlay(width:height:)`, `augment(rgba:width:height:)`).
Everything behind it is a value type; `DiceKeyScanner` is the only class.

## How the port was validated without a Mac

There is no Swift compiler on the Linux container this was written in for Apple
frameworks, but the port uses none: it compiles and runs with the Linux Swift 6.1 toolchain
(`-swift-version 6 -strict-concurrency=complete`, no warnings). Validation went in two steps:

1. **fakecv.** The ten OpenCV routines the C++ scanner calls (`cvtColor`, `medianBlur`,
   `Canny`, `dilate`, `threshold`, `findContours`, `arcLength`, `contourArea`, `minAreaRect`,
   `pointPolygonTest`, `getRotationMatrix2D` + `warpAffine`) were first written from scratch
   in C++ (the design of the Swift code), compared pixel for pixel and contour for contour
   against the real OpenCV 4.6 on every corpus photo, and then the unmodified vendored C++
   scanner was built on top of them. Its output over the corpus equals the real-OpenCV
   reference (`Tests/ReadDiceKeyTests/Fixtures/reference-cpp-scanner.json`) on every photo:
   identical human-readable read, `complete` flag and `totalError`; only some undoverline
   endpoints differ by a few pixels (see "minAreaRect ties" below).
2. **The Swift port** was then run on Linux over the same RGBA frames (decoded by OpenCV, as
   the reference was). Result on all 23 photos: identical human-readable read, `complete`
   and `totalError`; every undoverline code, orientation and first OCR choice identical;
   endpoints within 6.4 px and centres within 1.9 px of the reference (the tie-break effect).
   One second-choice OCR character differs on five faces.

Speed (x86 VM, `-O`): 250 ms for a 1768x1772 frame, 30-40 ms for a 550x550 one; a 1080x1080
frame extrapolates to ~95 ms on that VM. Measured on an Apple M2 with Xcode 27.0
(`SCANNER_BENCHMARK=1 swift test -c release --filter ScannerBenchmark`, corpus photo scaled
to the app's 1080x1080 centred square, median of 11 runs): **49 ms at `-O`, 5.8 s at
`-Onone`** as first ported. Because of the second number `Package.swift` compiles
`ReadDiceKey` with `-O` in Debug too; before that a Debug run from Xcode could not scan.

Stage profile of those 49 ms (single thread): the 13 contour passes 24 ms (of which the
label-plane fill and scan alone cost 0.8 ms per pass, and the Canny level and the level at
threshold 156 each 6-7 ms because they have ~4000 borders), Canny 7.4 ms, minAreaRect +
contourArea for the ~2100 rectangles 5.5 ms, the 12 thresholded copies 1.9 ms, everything
after the rectangles (undoverline reading, grid, OCR) about 4 ms. Three output-identical
changes followed (`docs/SCANNER-PORT-NOTES.md` "Performance" below), bringing the frame to
**20 ms on the M2** (8 cores). An A-series phone is still unmeasured; it has fewer cores,
so expect the level-0 chain (Canny + its contour pass, ~14 ms single-threaded on the M2) to
set the floor there.

## Performance

`findRectangles` (`FindUndoverlines.swift`) is where the time goes, and it is the one place
that deviates structurally from the C++:

* **The thirteen levels run concurrently** (`DispatchQueue.concurrentPerform`, one contour
  scratch plane per worker; level 0, the expensive Canny chain, gets a worker of its own).
  Results are concatenated in level order, so `removeOverlappingRectangles` sees the same
  sequence as the sequential C++ and its "first of equals wins" tie-breaks are unchanged.
* **Levels whose threshold exceeds the brightest pixel are skipped.** Their binarisation is
  all zero and has no contours, so nothing changes; on a typical photo that is 3 of the 12.
* **The threshold is fused into the label fill** (`findContours(in:atLeast:scratch:)`): the
  `gray >= t` image is never materialised.
* **Canny's planes** are 16-bit (|dx| + |dy| is at most 36720, so the magnitudes are `UInt16`) and left
  uninitialised where the pass overwrites them.

Verified by dumping `readResultJSON` and the finished flag for all 23 corpus photos at
native size and at 1080x1080 before and after: byte-identical. The scanner's public API is
still synchronous; the app calls it from an actor with a user-initiated task so the workers
land on performance cores.

## Pipeline, stage by stage

| Stage | Swift | C++ source |
|---|---|---|
| RGBA to gray (OpenCV's fixed-point luma) | `GrayImage.init(rgba:width:height:)` | `read-dicekey.cpp` `processRGBAImage` (`cvtColor RGBA2GRAY`) |
| 3x3 median blur, Canny (253, 255, aperture 5), 3x3 dilate | `GrayImage.medianBlur3/canny5/dilate3` | `graphics/find-rectangles.cpp` lines 59-80 |
| 12 fixed thresholds `gray >= (l+1)*255/13` | `GrayImage.thresholdAtLeast` | `find-rectangles.cpp` line 87 |
| Contours (RETR_LIST, CHAIN_APPROX_SIMPLE) of each binarisation | `findContours(in:scratch:)` | `find-rectangles.cpp` line 92 |
| Perimeter >= 50 filter, minAreaRect, contourArea | `findRectangles`, `RectangleDetected` | `find-rectangles.cpp` lines 94-100, `graphics/rectangle.h` |
| Shape filter (width/length within 1.5x of 0.177), modal area (35-wide mode, 25% band), modal angle, overlap removal with penalty | `findCandidateUndoverlines`, `findTighestModalAreaOfRects`, `removeOverlappingRectangles` | `find-undoverlines.cpp` lines 20-108, `find-rectangles.cpp` lines 10-44 |
| Rectangle to line: integer corners, 31 samples, bimodal threshold (4/4), 3% extension, trim to dark pixels | `undoverlineRectToLine`, `RRectCorners`, `samplePoint*`, `bimodalThreshold` | `find-undoverlines.cpp` lines 111-198, `graphics/sample-point.h`, `utilities/statistics.h` |
| 11 dot samples, bimodal threshold (4 black/4 white), bits, 11-bit decode, face code lookup, inferred face centre and opposite line | `readUndoverline`, `Undoverline.init`, `decodeUndoverline11Bits`, `DiceKeyFaceSpecification` | `find-undoverlines.cpp` lines 200-217, `undoverline.cpp`, `decode-die.cpp`, `dicekey-face-specification.cpp` |
| Sort by inferred centre y; pair underlines with overlines within a quarter face | `findReadableUndoverlines`, `findFacesAndStrayUndoverlines` | `find-undoverlines.cpp` lines 219-256, `find-faces.cpp` |
| Grid model: a face with 4 others in its row and column (within 1.0 face width, see below), even spacing (5% or 1/5 of the perpendicular step) | `calculateDiceKeyGrid`, `GridProximity`, `findAndValidateMeanDifference` | `assemble-dicekey.cpp` lines 90-200, `graphics/geometry.h`, `statistics.h` |
| Place faces and strays into the 25 slots (within 0.25 of a face), read the opposite line of a stray where it should be | `orderFacesAndInferMissingUndoverlines`, `DiceKeyGridModel.inferFaceIndexFromCenterPoint` | `assemble-dicekey.cpp` lines 202-271 |
| Per face: threshold = mean of the two lines' thresholds, rotate/crop text region (warpAffine), binary threshold, split at the centre gap, template OCR | `readFaces`, `readCharactersOnFace`, `GrayImage.copyRotatedRectangle`, `findClosestMatchingCharacter` | `read-faces.cpp`, `read-face-characters.cpp`, `graphics/rotate.h`, `simple-ocr.cpp` |
| Orientation = round((faceAngle - gridAngle) / 90 degrees) mod 4 | `readFaces` | `read-faces.cpp` lines 54-62 |
| Face error (0 / hamming distance / 2 / 8 / 255), majority letter and digit | `FaceRead.error()`, `letter`, `digit` | `face-read.cpp` |
| Merge with the previous frame (potential match in one of four rotations, keep the lower-error face) | `DiceKeyRead.mergePrevious`, `isPotentialMatch`, `rotate` | `lib-dicekey/dicekey.hpp` |
| Termination: total error 0, or max error <= 2 and > 4000 ms since the last improvement | `DiceKeyReader.process(gray:)` | `read-dicekey.cpp` lines 15-16, 51-75 |
| JSON | `DiceKeyReader.jsonDiceKeyRead` | `dicekey.hpp toJson`, `face-read.cpp toJson`, `undoverline.cpp toJson`, `json.cpp` |
| Overlay: face box on error, undoverline boxes, glyph outlines in green/orange/red | `visualizeReadResults`, `writeFaceCharacters`, `RGBACanvas` | `visualize-read-results.cpp`, `write-face-characters.cpp`, `graphics/draw-rotated-rect.cpp` |
| Glyph model (70x53 penalty nibbles, 213x280 outlines) | `OcrFontTables.swift` (generated), `GlyphTemplates` | `externally-generated/inconsolata-700.cpp`, `ocr-font.h`, `font.h` |

Every constant above is kept as in the C++ and commented with its origin at the point of use.
Types follow the C++: `Float` where it used `float`, `Double` where it used `double`, and the
two rounding conventions are separate helpers: `cvRound` (half to even, what `cv::Point2f`
to `cv::Point` conversion does on arm64/x86-64) and `cRoundToInt` (C `round()`, half away
from zero, where the code calls `round` explicitly).

## Contour strategy

Suzuki and Abe border following, written directly (`Contours.swift`), not Vision.
`VNDetectContoursRequest` applies its own contrast/blur preprocessing, simplifies the
polygons and returns normalised coordinates, so its rectangles would not match the C++
scanner's and nothing downstream (modal area, overlap removal, integer corners) could be
compared against the reference. The tracer reproduces `cv::findContours(RETR_LIST,
CHAIN_APPROX_SIMPLE)` exactly on the corpus: same borders, same point sequences (including
OpenCV's rule of dropping the start pixel when the chain runs straight through it), same
list order (most recently found first), with a one-pixel zero border around the image.
The label plane is `Int32` (border counts exceed 65k on the largest photos) and is reused
across the 13 binarisations of a frame.

## Where the Swift deliberately differs

* **`orientationAsLowercaseLetterTrbl` is JSON `null` instead of `"?"`** for a face that could
  not be oriented. The app decodes the field as `FaceOrientationLetterTrbl?` (t/r/b/l); `"?"`
  made the whole array fail to decode. Absent undoverlines are `null` as in the C++.
* **JSON number formatting.** The C++ printed floats with `std::to_string` (six decimals);
  `JSONEncoder` prints shortest round-trip representations (`130` instead of
  `130.000000`). Keys are sorted. Structure is identical. Non-finite values encode as 0.
* **minAreaRect ties.** OpenCV's rotating calipers and this port both return the minimum-area
  box, but when two hull edges give exactly the same area they can choose different ones
  (a box rotated 90 degrees with width/height swapped is the same box, but some ties are
  different boxes of equal area). This changes which of several overlapping candidate
  rectangles wins and moves the fitted line by a few pixels; decoded bits, codes and OCR
  were unaffected on the corpus. The `minAreaRect` angle is normalised to [0, 90) as OpenCV
  4.5.1+ does; the scanner only uses angles modulo 90 or through `points()`.
* **`FaceRead.error()` guards `ocr...[1]`** (the C++ indexes it unconditionally; strings are
  always two characters when non-empty, so behaviour is the same).
* **`writeFaceCharacters` clips every pixel.** The C++ bounds check used `||` and could write
  outside the buffer.
* **Thick overlay lines** use a square brush; OpenCV's thick `LINE_8` polylines have slightly
  different end caps. Cosmetic.
* **`bimodalThreshold` cannot throw.** With fewer than two samples (never the case here: 31
  and 11 samples) it returns 0 rather than throwing; the C ABI shim swallowed the exception
  anyway.
* **`getImageOfFace` / `FaceRead::imageData` is not ported**: the C ABI never exposed the
  colour crops of error faces, and the app never used them.
* **`DiceKeyScanner.reader` is internal** (not private) so tests can inspect the pipeline.
* **Non-finite arithmetic never traps.** Where the C++ would have converted NaN/inf to `int`
  (undefined behaviour), the Swift maps it to 0 or treats the face as unreadable
  (`cvRound`, `cRoundToInt`, `readCharactersOnFace`, `inferFaceIndexFromCenterPoint`).
* **`findTighestModalAreaOfRects` searches every centre.** The C++ loop bound
  (`count - (halfModeSize + 2)`) skipped the last two centres, and for 26, 28, ... 36
  candidates it skipped all of them and returned NaN, which then filtered out every
  undoverline in the frame. The corpus and reference comparison are unchanged by the fix.

## Upstream quirks kept on purpose

* `whenLastImproved` is refreshed when the merged key's total error is *greater* than the
  previous one (`read-dicekey.cpp` lines 59-62). In practice the four-second budget counts
  from the first complete read. Kept, with a comment.
* `orderFacesAndInferMissingUndoverlines` passes its `maxMmFromRowOrColumnLine = 1.0` into
  `calculateDiceKeyGrid` as a *fraction of a face width*, so the row/column tolerance is a
  whole face width rather than the 0.1 default. Kept.
* Faces with neither line keep centre (0, 0): the C++ constructs a centre-only subclass but
  slices it when storing it in `vector<FaceUndoverlines>`. Kept (the overlay draws that
  box at the origin, as before).
* `inferredSizeInPixels` halves only the overline length (C++ operator precedence). Kept;
  it is unused by the shipping path.
* The threshold levels use the *unblurred* gray image; only Canny sees the median blur.

## `// VERIFY` sites

* `OCR.swift` `findClosestMatchingCharacter`: `std::sort` is unstable; ties between
  characters with equal penalty keep table order here. No corpus face has a tied first
  choice, but a tie would change the second choice string.
* `DiceKeyReader.swift` timing: `ContinuousClock` duration converted to whole milliseconds
  compared `> 4000`, as `duration_cast<milliseconds>(...).count() > 4000` did. Check the
  four-second fallback on device with a key that has a persistent 1-2 bit error.
* Performance on an A-series chip: 49 ms per 1080x1080 frame on an M2 (see "Speed" above),
  so the budget is fine on Apple silicon; run the benchmark on the phone once one is
  attached. If it were ever over budget, the profile is dominated by the 13 contour passes
  and Canny (`GrayImage.canny5`, `findContours`); the tracer's label plane and the Sobel
  planes are the memory-bound loops.
* `ReferenceScannerComparisonTests` tolerances (10 px endpoints, 4 px centres) were set from
  frames decoded by OpenCV's libjpeg; ImageIO decodes the corpus JPEGs slightly differently,
  which may move a tie-break or two. A failure there that is *only* an endpoint distance
  with identical codes, orientation and OCR is that effect, not a port bug.

## Tests

* `ScannerCorpusTests` (acceptance): unchanged.
* `ReferenceScannerComparisonTests` (new): per face, compares undoverline codes, presence,
  endpoints, centre, orientation and first OCR characters against
  `reference-cpp-scanner.json`, and names the face and field that diverged.
* `DiceKeyScannerTests` (smoke): unchanged.
* `ModalAreaTests` (new): the modal-area search returns an area for every candidate count.
* `ScannerBenchmarkTests` (opt-in, `SCANNER_BENCHMARK=1`): per-frame timing on a 1080 px
  square; skipped on CI.

## Regenerating the font tables

`python3 scripts/generate-ocr-font-tables.py` rewrites
`Sources/ReadDiceKey/OcrFontTables.swift` from the vendored `inconsolata-700.cpp`,
verifying the table sizes and that the run-length outlines round-trip. Once
`ReadDiceKeyNative` is deleted, keep a copy of that one C++ file (or the generated Swift is
the source of record).
