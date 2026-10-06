#!/bin/sh
# Copy the desk counter's code into the website so the phone remote's live
# preview draws exactly what the boxes draw. Run after changing desk/firmware/mad.
set -e
cd "$(dirname "$0")/.."
mkdir -p website/public/desk/py/mad
cp desk/firmware/mad/*.py website/public/desk/py/mad/
rm -f website/public/desk/py/mad/main.py      # the board's hardware loop: not needed
echo "synced desk/firmware/mad -> website/public/desk/py/mad"
