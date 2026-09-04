#!/bin/bash
# 构建 MenuNote.app：swift build release -> 组装 .app 包 -> ad-hoc 签名
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

APP="build/MenuNote.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp ".build/$CONFIG/MenuNote" "$APP/Contents/MacOS/MenuNote"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>MenuNote</string>
    <key>CFBundleIdentifier</key>
    <string>com.menunote.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MenuNote</string>
    <key>CFBundleDisplayName</key>
    <string>MenuNote 便签</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "==> 构建完成: $APP"
