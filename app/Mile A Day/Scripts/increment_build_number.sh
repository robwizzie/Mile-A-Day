#!/bin/bash

# Auto-increment build number script for Mile A Day
# This script increments the CFBundleVersion in Info.plist
# Add this to Xcode Build Phases > New Run Script Phase

set -e

# Get the Info.plist path
INFO_PLIST="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"
PROJECT_INFO_PLIST="${SRCROOT}/Mile A Day/Info.plist"

# If we're in a build environment and have an Info.plist
if [ -f "${PROJECT_INFO_PLIST}" ]; then
    # Get current build number
    BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${PROJECT_INFO_PLIST}")
    
    # Increment build number
    NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))
    
    # Update build number in Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_BUILD_NUMBER}" "${PROJECT_INFO_PLIST}"
    
    echo "Build number incremented from ${BUILD_NUMBER} to ${NEW_BUILD_NUMBER}"
else
    echo "Info.plist not found at ${PROJECT_INFO_PLIST}"
fi

# Alternative approach using git commit count as build number
# Uncomment the lines below if you prefer using git commit count
#
# if git rev-parse --git-dir > /dev/null 2>&1; then
#     GIT_COMMIT_COUNT=$(git rev-list --count HEAD)
#     /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${GIT_COMMIT_COUNT}" "${PROJECT_INFO_PLIST}"
#     echo "Build number set to git commit count: ${GIT_COMMIT_COUNT}"
# fi 