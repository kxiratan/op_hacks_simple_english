#!/bin/bash
# Builds Easy Peasy and wraps it in an .app bundle so macOS can give it its own
# Screen Recording permission (a bare binary borrows the Terminal's instead).
# Usage: scripts/bundle.sh        then: open build/EasyPeasy.app
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64

APP="build/EasyPeasy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/arm64-apple-macosx/release/EasyPeasy "$APP/Contents/MacOS/EasyPeasy"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Easy Peasy</string>
    <key>CFBundleDisplayName</key><string>Easy Peasy</string>
    <key>CFBundleIdentifier</key><string>com.easypeasy.widget</string>
    <key>CFBundleExecutable</key><string>EasyPeasy</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Easy Peasy reads the text of the webpage open in your browser so it can translate or simplify it when you click Peasify.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run locally. Because it changes with every build,
# macOS may ask for the Screen Recording permission again after a rebuild.
codesign --force --sign - "$APP"
echo "Built $APP"
