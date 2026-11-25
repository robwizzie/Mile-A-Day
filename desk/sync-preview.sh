#!/bin/sh
# Copy the desk counter's code into the website so the phone remote's live
# preview draws exactly what the boxes draw. Run after changing desk/firmware/mad.
set -e
cd "$(dirname "$0")/.."
mkdir -p website/public/desk/py/mad
cp desk/firmware/mad/*.py website/public/desk/py/mad/
rm -f website/public/desk/py/mad/main.py      # the board's hardware loop: not needed
# The laundry plug script (the remote fills in the plug's key).
mkdir -p website/public/desk/laundry
cp desk/laundry/mad-laundry.js website/public/desk/laundry/
echo "synced desk/firmware/mad -> website/public/desk/py/mad"
