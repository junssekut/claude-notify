#!/bin/bash
set -e

APP_NAME="ClaudeNotify"
# Do NOT revert to com.claude.notify. macOS caches an app's notification icon
# against its bundle id, and that id first registered before this bundle had any
# icon, so it permanently served a generic placeholder. Reinstalling, re-signing,
# CFBundleVersion bumps and killing usernoted/iconservicesagent all fail to reset
# it; only a fresh bundle id does. Changing this re-prompts for notification
# permission. The client/daemon IPC channel is NOTIF_NAME in Sources/main.swift,
# not this value, so it is safe to change.
BUNDLE_ID="com.junskii.claudenotify"
BUILD_DIR=".build/release"
# Bump when bundle resources change (Dock/Finder icon refresh).
BUNDLE_VERSION="7"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ICON_SVG="Resources/claude-logo.svg"
ICON_ICNS="Resources/AppIcon.icns"
SOUND_FILES=(huh-1 huh-2 huh-3 last)

echo "Building..."
swift build -c release

# Regenerate the app icon when the .icns is missing or older than the source art.
if [ ! -f "$ICON_ICNS" ] || [ "$ICON_SVG" -nt "$ICON_ICNS" ]; then
    echo "Generating app icon..."
    swift scripts/make-icon.swift
    iconutil -c icns .build/AppIcon.iconset -o "$ICON_ICNS"
fi

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/claude-notify" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ICON_ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
for snd in "${SOUND_FILES[@]}"; do
    cp "Resources/$snd.mp3" "$APP_BUNDLE/Contents/Resources/"
done

cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Notify</string>
    <key>CFBundleVersion</key>
    <string>$BUNDLE_VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
</dict>
</plist>
EOF

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

echo "Signing..."
codesign --force --sign - --options runtime --timestamp=none "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
codesign --force --sign - --options runtime --timestamp=none "$APP_BUNDLE"

echo "Done: $APP_BUNDLE"
echo ""
echo "Install with:"
echo "  rm -rf /Applications/$APP_NAME.app"
echo "  cp -r $APP_BUNDLE /Applications/"
echo ""
echo "Run daemon:"
echo "  open /Applications/$APP_NAME.app"
echo ""
echo "CLI wrapper (add to ~/.zshrc):"
echo "  alias claude-notify='/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME'"
