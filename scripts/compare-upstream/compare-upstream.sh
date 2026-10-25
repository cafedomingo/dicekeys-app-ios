#!/usr/bin/env bash
# Reads the scanner's photo corpus and video with upstream dicekeys/read-dicekey (C++ on OpenCV) as
# well as with this repo's scanner, scores both as ScannerCorpusTests scores, and prints Markdown
# tables. docs/scanning.md, "Against read-dicekey", gives the method and the results.
#
#   scripts/compare-upstream/compare-upstream.sh [work dir]
#
# UpstreamCompareTests writes the corpus as gray frames, one per photo at each corpus size and per
# video frame, and this scanner's reads of them; upstream-read reads the same frames; score.py
# scores both. The work dir (default $TMPDIR/upstream-compare) keeps those and what is built for
# them, which a later run reuses. The first run builds OpenCV 4.12.0 (core and imgproc, the version
# upstream's extern/opencv.cmake pins) and upstream at UPSTREAM_COMMIT, about 90 s. It needs Xcode,
# git, python3 and the network; cmake and ninja come from PATH or are pip-installed into the work dir.
set -euo pipefail

UPSTREAM_COMMIT=04400368ff3fa82f3eb19f06fb7bebc67a789603
OPENCV_VERSION=4.12.0

here=$(cd "$(dirname "$0")" && pwd)
package=$here/../../Packages/ReadDiceKey
work=${1:-${TMPDIR:-/tmp}/upstream-compare}
mkdir -p "$work"
work=$(cd "$work" && pwd)
log=$work/build.log
: >"$log"
trap 'echo "Failed; see $log" >&2' ERR

if ! command -v cmake >/dev/null || ! command -v ninja >/dev/null; then
    [ -x "$work/venv/bin/cmake" ] || { python3 -m venv "$work/venv" && "$work/venv/bin/pip" install -q cmake ninja; } >>"$log" 2>&1
    PATH=$work/venv/bin:$PATH
fi

upstream=$work/read-dicekey
if [ ! -d "$upstream" ]; then
    git init -q "$upstream"
    git -C "$upstream" fetch -q --depth 1 https://github.com/dicekeys/read-dicekey.git "$UPSTREAM_COMMIT" >>"$log" 2>&1
    git -C "$upstream" checkout -q FETCH_HEAD
fi

opencv=$work/opencv-$OPENCV_VERSION
if [ ! -d "$opencv/lib" ]; then
    [ -d "$work/opencv-src" ] ||
        git clone -q --depth 1 --branch "$OPENCV_VERSION" https://github.com/opencv/opencv.git "$work/opencv-src" >>"$log" 2>&1
    cmake -S "$work/opencv-src" -B "$work/opencv-build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$opencv" -DBUILD_LIST=core,imgproc -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF \
        -DBUILD_opencv_apps=OFF -DBUILD_JAVA=OFF -DBUILD_opencv_python3=OFF -DWITH_OPENCL=OFF \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 >>"$log" 2>&1
    cmake --build "$work/opencv-build" --target install >>"$log" 2>&1
fi

# Upstream's CMake builds its two libraries from these globs, C++11, Release.
clang++ -std=c++11 -O3 -DNDEBUG -w -I"$upstream/lib-dicekey" -I"$upstream/lib-read-dicekey" \
    -I"$opencv/include/opencv4" "$upstream"/lib-dicekey/*.cpp "$upstream"/lib-dicekey/*/*.cpp \
    "$upstream"/lib-read-dicekey/*.cpp "$upstream"/lib-read-dicekey/*/*.cpp "$here/upstream-read.cpp" \
    -L"$opencv/lib" -lopencv_imgproc -lopencv_core -Wl,-rpath,"$opencv/lib" -o "$work/upstream-read" >>"$log" 2>&1

corpus=$work/corpus
rm -rf "$corpus"
UPSTREAM_COMPARE_DIR=$corpus swift test -c release --package-path "$package" --filter UpstreamCompare >>"$log" 2>&1

tail -n +2 "$corpus/repo-photos.tsv" | cut -f1 | "$work/upstream-read" >"$corpus/upstream-photos.tsv"
tail -n +2 "$corpus/repo-video.tsv" | cut -f1 | "$work/upstream-read" --merge >"$corpus/upstream-video-merged.tsv"
tail -n +2 "$corpus/repo-video.tsv" | cut -f1 | "$work/upstream-read" >"$corpus/upstream-video-single.tsv"

python3 -I "$here/score.py" "$corpus" "$upstream/tests/test-lib-read-dicekey/img"
