#!/bin/bash
# Exports every Flamey wardrobe item, drawn by today's Swift code, into
# app/FlameyExport/out/ (see FlameyExporter.swift). macOS + Xcode only; no
# project, no simulator: it compiles the widget extension's Flamey files, a
# RECORDING copy of FlameyArt.swift (GraphicsContext → RecContext) and the
# exporter into a command-line tool and runs it.
#
#   bash app/FlameyExport/run.sh
#
# Everything it says also lands in out/compile.log and out/run.log.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
W="$HERE/../MileADayWidgets"
OUT="$HERE/out"
BUILD="$(mktemp -d)"
BIN="$BUILD/flamey-export"

rm -rf "$OUT"
mkdir -p "$OUT"

# The recording copy: only `enum FlameyArt { … }` (its FlameyLook extension
# already exists in the real file), renamed so both compile side by side.
awk '/^enum FlameyArt / { on = 1 } on { print } on && /^}/ { exit }' "$W/FlameyArt.swift" \
  | perl -pe 's/\bGraphicsContext\b/RecContext/g; s/\bFlameyArt\b/FlameyArtRec/g' \
  > "$BUILD/FlameyArtRec.swift"
{ echo "import SwiftUI"; cat "$BUILD/FlameyArtRec.swift"; } > "$BUILD/FlameyArtRec2.swift"
mv "$BUILD/FlameyArtRec2.swift" "$BUILD/FlameyArtRec.swift"

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
    "$BUILD/FlameyArtRec.swift" \
    "$HERE/RecContext.swift" \
    "$HERE/FlameyExporter.swift" \
    -o "$BIN" > "$OUT/compile.log" 2>&1; then
  cp "$BUILD/FlameyArtRec.swift" "$OUT/FlameyArtRec.swift"
  echo "COMPILE FAILED. First errors:"
  grep -m 15 "error:" "$OUT/compile.log"
  exit 1
fi

echo "Step 2/2: drawing every item…"
if ! "$BIN" "$OUT" > "$OUT/run.log" 2>&1; then
  echo "EXPORT FAILED. Last lines:"
  tail -n 15 "$OUT/run.log"
  exit 1
fi

tail -n 5 "$OUT/run.log"
echo "Done: $(find "$OUT" -type f | wc -l | tr -d ' ') files in $OUT"
rm -rf "$BUILD"
