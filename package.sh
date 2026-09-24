#!/bin/bash
# Build a distributable Learn: universal (Apple Silicon + Intel), signed, as dist/Learn.dmg and dist/Learn.zip.
# Install: open the DMG, drag Learn to Applications, open it (Settings shows the permissions to grant).
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
swift build -c release --arch arm64 --arch x86_64
BIN=.build/apple/Products/Release/Learn

STAGE=$(mktemp -d)/Learn
APP="$STAGE/Learn.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Learn"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | awk -F'"' 'NR==1{print $2}')}"
codesign --force --timestamp=none --sign "${SIGN_ID:--}" --identifier com.erluxman.learn "$APP"
codesign --verify --strict "$APP"

ln -s /Applications "$STAGE/Applications"
mkdir -p dist
rm -f dist/Learn.dmg dist/Learn.zip
hdiutil create -quiet -volname "Learn $VERSION" -srcfolder "$STAGE" -format UDZO -ov dist/Learn.dmg
ditto -c -k --keepParent "$APP" dist/Learn.zip
rm -rf "$(dirname "$STAGE")"

echo "Built Learn $VERSION ($(lipo -archs "$BIN"))"
ls -lh dist/
