#!/bin/bash
# Adds every user-facing string the app module uses to Localizable.xcstrings,
# the way Xcode's "Use Compiler to Extract Swift Strings" does: the compiler
# emits .stringsdata with the exact runtime keys (Int → %lld, String → %@),
# then xcstringstool merges them. Additive: nothing is marked stale.
#
#   bash app/sync-strings.sh
#
# New keys arrive untranslated; translate them (German at least) before
# shipping. Takes a few minutes (a whole-module -Onone compile).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if ! xcrun --sdk iphoneos --show-sdk-path > /dev/null 2>&1; then
  XCODE=$(ls -d /Applications/Xcode*.app 2>/dev/null | sort | tail -1)
  export DEVELOPER_DIR="$XCODE/Contents/Developer"
fi
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cd "$HERE"
find "Mile A Day" -name '*.swift' -print0 > "$WORK/files"
echo "Compiling to extract strings…"
xargs -0 xcrun swiftc -c -wmo -Onone -parse-as-library -module-name Mile_A_Day \
  -sdk "$SDK" -target arm64-apple-ios17.0 -swift-version 5 \
  -emit-localized-strings -emit-localized-strings-path "$WORK/sd" \
  -o "$WORK/module.o" < "$WORK/files"

CATALOG="$HERE/Mile A Day/Localizable.xcstrings"
before=$(grep -c '^    "' "$CATALOG" || true)
xcrun xcstringstool sync "$CATALOG" --stringsdata "$WORK"/sd/*.stringsdata --skip-marking-strings-stale
after=$(grep -c '^    "' "$CATALOG" || true)
echo "Catalog keys: $before → $after"
