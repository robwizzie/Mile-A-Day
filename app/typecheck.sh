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

# The iPhone SDK ships inside Xcode, not the Command Line Tools: if xcrun is
# pointed at the tools (xcode-select), use the newest Xcode in /Applications.
if ! xcrun --sdk iphoneos --show-sdk-path > /dev/null 2>&1; then
  XCODE=$(ls -d /Applications/Xcode*.app 2>/dev/null | sort | tail -1)
  if [ -z "$XCODE" ]; then
    echo "No Xcode found in /Applications — the iPhone SDK comes with Xcode."
    exit 1
  fi
  export DEVELOPER_DIR="$XCODE/Contents/Developer"
  echo "Using $XCODE"
fi
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
status=0

# check <name> <folder> [extra files…]
check() {
  local name="$1" dir="$2" log="$HERE/typecheck-$1.log"
  shift 2
  local list
  list=$(mktemp)
  find "$dir" -name '*.swift' -print0 > "$list"
  for f in "$@"; do printf '%s\0' "$f" >> "$list"; done
  echo "Type-checking $name ($(tr -dc '\0' < "$list" | wc -c | tr -d ' ') files)…"
  if xargs -0 xcrun swiftc -typecheck \
      -sdk "$SDK" -target arm64-apple-ios17.0 -swift-version 5 < "$list" > "$log" 2>&1; then
    echo "  $name: OK"
  else
    echo "  $name: FAILED — first errors:"
    grep -m 12 "error:" "$log" | sed "s#$HERE/##"
    status=1
  fi
}

check app "$HERE/Mile A Day"
# The widget extension also compiles these app-folder files (its membership
# exceptions in the Xcode project).
check widgets "$HERE/MileADayWidgets" \
  "$HERE/Mile A Day/Shared/WidgetDataStore.swift" \
  "$HERE/Mile A Day/Widgets/StreakCountWidget.swift" \
  "$HERE/Mile A Day/Widgets/TodayProgressWidget.swift" \
  "$HERE/Mile A Day/Widgets/WorkoutLiveActivity.swift"
exit $status
