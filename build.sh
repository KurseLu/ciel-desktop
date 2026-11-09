#!/bin/zsh
# 在本機編出 夏爾.app（arm64，ad-hoc 簽名）
set -e
cd "${0:A:h}"
APP="夏爾.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O CielPet.swift -o "$APP/Contents/MacOS/CielPet"
cp -R frames "$APP/Contents/Resources/frames"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>夏爾</string>
<key>CFBundleIdentifier</key><string>com.kurselu.ciel-pet</string>
<key>CFBundleExecutable</key><string>CielPet</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
P
codesign -s - --force "$APP"
echo built "$APP"
