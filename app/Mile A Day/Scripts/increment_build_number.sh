#!/bin/bash

# Auto-increment build number script for Mile A Day
# Increments CFBundleVersion each build.

set -e

# Full path to Info.plist for the current target (handles spaces automatically)
PLIST_PATH="${PROJECT_DIR}/${INFOPLIST_FILE}"

if [ ! -f "${PLIST_PATH}" ]; then
  echo "[BuildNumber] ❌ Info.plist not found at path: ${PLIST_PATH}"
  exit 1
fi

# Read current build number (defaults to 0 if missing)
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${PLIST_PATH}" 2>/dev/null || echo "0")

# Ensure numeric build number
if ! [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
  echo "[BuildNumber] ⚠️  Current build (CFBundleVersion) is not numeric: $CURRENT_BUILD. Resetting to 0."
  CURRENT_BUILD=0
fi

NEW_BUILD=$((CURRENT_BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "${PLIST_PATH}"

echo "[BuildNumber] ✅ Incremented build number: ${CURRENT_BUILD} -> ${NEW_BUILD}"

exit 0

# Alternative approach using git commit count as build number
# Uncomment the lines below if you prefer using git commit count
#
# if git rev-parse --git-dir > /dev/null 2>&1; then
#     GIT_COMMIT_COUNT=$(git rev-list --count HEAD)
#     /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${GIT_COMMIT_COUNT}" "${PROJECT_INFO_PLIST}"
#     echo "Build number set to git commit count: ${GIT_COMMIT_COUNT}"
# fi 