#!/bin/bash
# Type-checks the main app and the widget extension on a Mac — the same
# check CI's "iOS (type-check)" job runs for the app (.github/workflows/ios.yml),
# plus the widget target, which CI does not check. No simulator, no project.
#
#   bash app/typecheck.sh
#
# Logs: app/typecheck-app.log, app/typecheck-widgets.log (gitignored).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
status=0

check() {
  local name="$1" dir="$2" log="$HERE/typecheck-$1.log"
  local count
  count=$(find "$dir" -name '*.swift' | wc -l | tr -d ' ')
  echo "Type-checking $name ($count files)…"
  if find "$dir" -name '*.swift' -print0 | xargs -0 xcrun swiftc -typecheck \
      -sdk "$SDK" -target arm64-apple-ios17.0 -swift-version 5 > "$log" 2>&1; then
    echo "  $name: OK"
  else
    echo "  $name: FAILED — first errors:"
    grep -m 12 "error:" "$log" | sed "s#$HERE/##"
    status=1
  fi
}

check app "$HERE/Mile A Day"
check widgets "$HERE/MileADayWidgets"
exit $status
