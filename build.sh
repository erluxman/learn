#!/bin/bash
# Build Learn.app, sign it, install to ~/Applications (Spotlight-indexed), relaunch.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/Learn.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Learn "$APP/Contents/MacOS/Learn"
cp Info.plist "$APP/Contents/Info.plist"

# Stable identity keeps the Accessibility grant across rebuilds (ad-hoc "-" resets it every build).
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | awk -F'"' 'NR==1{print $2}')}"
codesign --force --sign "${SIGN_ID:--}" --identifier com.erluxman.learn "$APP"

pkill -x Learn || true
mkdir -p ~/Applications
rm -rf ~/Applications/Learn.app
ditto "$APP" ~/Applications/Learn.app && rm -rf build   # one copy only, so Spotlight opens the right one
mdimport ~/Applications/Learn.app 2>/dev/null || true
[[ "${1:-}" == "--no-open" ]] || open ~/Applications/Learn.app
echo "Installed ~/Applications/Learn.app"
