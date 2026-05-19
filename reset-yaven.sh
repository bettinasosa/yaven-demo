#!/bin/bash
# Resets Yaven to a completely fresh state — as if it has never been run.
# Run this before each test rebuild, then relaunch from Xcode.

set -e

echo "Killing Yaven if running..."
pkill -x "leanring-buddy" 2>/dev/null || true
sleep 0.5

echo "Clearing UserDefaults (com.yavenlabs.yaven)..."
defaults delete com.yavenlabs.yaven 2>/dev/null || true

echo "Clearing legacy UserDefaults suites..."
defaults delete com.humansongs.clicky 2>/dev/null || true
defaults delete com.yourcompany.leanring-buddy 2>/dev/null || true
defaults delete com.yourcompany.yaven 2>/dev/null || true

echo "Deleting Yaven application support files..."
rm -rf "$HOME/Library/Application Support/Yaven"

echo "Done. Launch from Xcode — you'll start at the Google Sign-In screen."
