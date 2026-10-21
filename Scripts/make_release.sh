#!/usr/bin/env bash
# 给某个工具出一个 release 包，并生成可直接粘进 manifest.json 的片段
#
# 用法：
#   Scripts/make_release.sh <app 路径> <工具 id> [更新说明]
#
# 例：
#   Scripts/make_release.sh build/A-Kit.app a-kit "首个版本"
#
# 输出（在 build/ 下）：
#   <Name>-<version>.zip     上传到 GitHub Release
#   manifest-entry.json      清单条目（含 sha256 / size）
set -euo pipefail
cd "$(dirname "$0")/.."

APP_PATH="${1:?用法: make_release.sh <app 路径> <工具 id> [说明]}"
TOOL_ID="${2:?缺工具 id}"
NOTES="${3:-}"

NAME="$(basename "$APP_PATH" .app)"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Contents/Info.plist")
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "13.0")

ZIP="build/$NAME-$VERSION.zip"
rm -f "$ZIP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP"

SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
SIZE=$(stat -f%z "$ZIP")

cat > "build/manifest-entry.json" <<JSON
{
  "id": "$TOOL_ID",
  "name": "$NAME",
  "bundleId": "$BUNDLE_ID",
  "channels": {
    "stable": {
      "version": "$VERSION",
      "build": $BUILD,
      "minOS": "$MIN_OS",
      "url": "https://github.com/<owner>/<repo>/releases/download/v$VERSION/$NAME-$VERSION.zip",
      "sha256": "$SHA",
      "size": $SIZE,
      "releasedAt": "$(date +%Y-%m-%d)",
      "notes": "$NOTES"
    }
  }
}
JSON

echo "✓ $ZIP"
echo "  sha256 $SHA"
echo "  size   $SIZE"
echo "  条目   build/manifest-entry.json"
echo
echo "下一步："
echo "  gh release create v$VERSION \"$ZIP\" --title \"$NAME $VERSION\" --notes \"$NOTES\""
echo "  然后把 build/manifest-entry.json 的内容合并进 manifest.json 的 tools 数组"
