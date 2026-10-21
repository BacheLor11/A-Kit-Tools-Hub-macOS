#!/usr/bin/env bash
# 打包 A-Kit.app（SwiftPM + 手工组 bundle，不依赖 Xcode 工程）
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="A-Kit"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
PY="${PYTHON:-python3}"

echo "▸ 编译 (release)…"
swift build -c release --disable-sandbox

echo "▸ 准备图标…"
if [ ! -f "$BUILD_DIR/AppIcon.icns" ]; then
    "$PY" Scripts/make_app_icon.py Resources/MarkA.png "$BUILD_DIR" >/dev/null
fi
MB_SRC="Resources/MenuBarIconSource.png"
[ -f "$MB_SRC" ] || MB_SRC="Resources/MarkA.png"
"$PY" Scripts/make_menubar_icon.py "$MB_SRC" "$BUILD_DIR" >/dev/null

echo "▸ 组装 ${APP} …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/AKitHub "$APP/Contents/MacOS/AKitHub"
cp .build/release/akit "$APP/Contents/MacOS/akit"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$BUILD_DIR/MenuBarIcon.png" "$APP/Contents/Resources/MenuBarIcon.png"
cp Resources/seed-manifest.json "$APP/Contents/Resources/seed-manifest.json"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ 签名 (ad-hoc)…"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "  ! 签名失败，先跳过"

# 生成 gh 上传用的压缩包
if [ "${1:-}" = "--release" ]; then
    echo "▸ 打包 zip…"
    rm -f "$BUILD_DIR/$APP_NAME-$VERSION.zip"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD_DIR/$APP_NAME-$VERSION.zip"
    shasum -a 256 "$BUILD_DIR/$APP_NAME-$VERSION.zip" | awk '{print "  sha256:", $1}'
fi

if [ "${1:-}" = "--install" ] || [ "${2:-}" = "--install" ]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
    echo "▸ 安装到 $DEST…"
    osascript -e 'tell application "A-Kit" to quit' 2>/dev/null || true
    sleep 0.5
    rm -rf "$DEST/$APP_NAME.app"
    /usr/bin/ditto "$APP" "$DEST/$APP_NAME.app"
    /usr/bin/xattr -dr com.apple.quarantine "$DEST/$APP_NAME.app" 2>/dev/null || true
    echo "✓ 完成：$DEST/$APP_NAME.app"
else
    echo "✓ 完成：$APP"
fi
