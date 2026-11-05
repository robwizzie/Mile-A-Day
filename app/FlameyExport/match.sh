#!/bin/bash
# The Flamey skins match check (see Match.swift). macOS + Xcode only: it
# compiles the widget extension's Flamey files with Match.swift and renders
# every item with the Swift art code and from backend/flamey-skins, side by
# side. Results land in app/FlameyExport/out/match-swift/.
#
#   bash app/FlameyExport/match.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
W="$HERE/../MileADayWidgets"
SKINS="$HERE/../../backend/flamey-skins"
OUT="$HERE/out"
BUILD="$(mktemp -d)"
BIN="$BUILD/flamey-match"
mkdir -p "$OUT"

echo "Step 1/2: compiling (about a minute)…"
if ! xcrun swiftc -parse-as-library -O -swift-version 5 \
    -target "$(uname -m)-apple-macos14.0" \
    "$W/FlameBuddyFigure.swift" \
    "$W/StreakFlameState.swift" \
    "$W/FlameyArt.swift" \
    "$W/FlameyMoodCore.swift" \
    "$W/FlameyPalettes.swift" \
    "$W/FlameyRender.swift" \
    "$W/FlameyWardrobe.swift" \
    "$W/FlameySkin.swift" \
    "$HERE/Match.swift" \
    -o "$BIN" > "$OUT/match-compile.log" 2>&1; then
  echo "COMPILE FAILED. First errors:"
  grep -m 15 "error:" "$OUT/match-compile.log"
  exit 1
fi

echo "Step 2/2: drawing every item both ways (a few minutes)…"
if ! "$BIN" "$SKINS" "$OUT" > "$OUT/match-run.log" 2>&1; then
  echo "MATCH FAILED TO RUN. Last lines:"
  tail -n 15 "$OUT/match-run.log"
  exit 1
fi
cat "$OUT/match-run.log"
rm -rf "$BUILD"
