#!/bin/bash
# 把一个 dylib 组装成 A-Kit 能加载的 .akitplugin
#
# 用法：
#   Scripts/package-plugin.sh <dylib> <输出目录> <插件ID> <显示名> <版本> [可执行名]
#
# 例：
#   Scripts/package-plugin.sh .build/release/libASweepPlugin.dylib dist \
#       com.aibao.ASweep "A-Sweep" 0.5.0

set -euo pipefail

DYLIB="${1:?缺少 dylib 路径}"
OUTDIR="${2:?缺少输出目录}"
PLUGIN_ID="${3:?缺少插件 ID}"
DISPLAY_NAME="${4:?缺少显示名}"
VERSION="${5:?缺少版本}"
EXEC_NAME="${6:-$(basename "$DYLIB" | sed -E 's/^lib//; s/\.dylib$//')}"

[[ -f "$DYLIB" ]] || { echo "找不到 $DYLIB"; exit 1; }

BUNDLE="$OUTDIR/$EXEC_NAME.akitplugin"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp "$DYLIB" "$BUNDLE/Contents/MacOS/$EXEC_NAME"
chmod +x "$BUNDLE/Contents/MacOS/$EXEC_NAME"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleIdentifier</key>
    <string>$PLUGIN_ID</string>
    <key>CFBundleName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$EXEC_NAME</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>AKPluginIdentifier</key>
    <string>$PLUGIN_ID</string>
    <key>AKPluginDisplayName</key>
    <string>$DISPLAY_NAME</string>
    <key>AKPluginABIVersion</key>
    <integer>1</integer>
</dict>
</plist>
PLIST

# ad-hoc 签名：本地分发够用。
# 以后走公证分发时，宿主要带 com.apple.security.cs.disable-library-validation，
# 否则 Team ID 不一致会被 Hardened Runtime 拒掉（已实测）。
codesign --force --sign - "$BUNDLE/Contents/MacOS/$EXEC_NAME" >/dev/null 2>&1 || true

echo "→ $BUNDLE"
