#!/bin/zsh
# usage: build.sh [sheet]  — compile the mock renderer and render sheet(s)
cd "$(dirname "$0")/src"
swiftc -parse-as-library -O -o ../mock *.swift 2>&1 | grep -E "error" | head -40
cd ..
./mock "${1:-all}"
