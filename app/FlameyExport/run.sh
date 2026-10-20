#!/bin/bash
# Exports every Flamey wardrobe item, drawn by today's Swift code, into
# app/FlameyExport/out/ (see FlameyExporter.swift). macOS + Xcode only; no
# project, no simulator: it compiles the widget extension's Flamey files with
# this exporter into a command-line tool and runs it.
#
#   bash app/FlameyExport/run.sh
#
# Everything it says also lands in out/compile.log and out/run.log.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
W="$HERE/../MileADayWidgets"
OUT="$HERE/out"
BIN_DIR="$(mktemp -d)"
BIN="$BIN_DIR/flamey-export"

rm -rf "$OUT"
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
    "$HERE/FlameyExporter.swift" \
    -o "$BIN" > "$OUT/compile.log" 2>&1; then
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
rm -rf "$BIN_DIR"
