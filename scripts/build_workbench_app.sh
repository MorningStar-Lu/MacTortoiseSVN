#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_HOME="$ROOT_DIR/.tmp-home"
MODULE_CACHE="$ROOT_DIR/.build/ModuleCache.noindex"
SWIFT_BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/debug"
RUST_BUILD_DIR="$ROOT_DIR/rust/target/debug"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="MacTortoiseSVN"
LEGACY_APP_NAME="MacSVNWorkbench"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_INFO_PLIST="$ROOT_DIR/Apps/MacSVNApp/Info.plist"
APP_ENTITLEMENTS="$ROOT_DIR/Apps/MacSVNApp/MacSVNWorkbench.entitlements"
XPC_INFO_PLIST="$ROOT_DIR/Apps/MacSVNStatusService/Info.plist"
XPC_BUNDLE_ID="com.morningstar.MacTortoiseSVN.StatusService"
XPC_BUNDLE="$APP_BUNDLE/Contents/XPCServices/$XPC_BUNDLE_ID.xpc"
FINDER_INFO_PLIST="$ROOT_DIR/Apps/MacSVNFinderSync/Info.plist"
FINDER_ENTITLEMENTS="$ROOT_DIR/Apps/MacSVNFinderSync/MacSVNFinderSync.entitlements"
FINDER_BUNDLE_ID="com.morningstar.MacTortoiseSVN.FinderSync"
FINDER_BUNDLE="$APP_BUNDLE/Contents/PlugIns/$FINDER_BUNDLE_ID.appex"
WORKBENCH_EXECUTABLE="$SWIFT_BUILD_DIR/$APP_NAME"
WORKBENCH_RESOURCE_BUNDLE="$SWIFT_BUILD_DIR/MacTortoiseSVN_MacSVNWorkbench.bundle"
XPC_EXECUTABLE="$SWIFT_BUILD_DIR/MacSVNStatusXPCService"
FINDER_EXECUTABLE="$SWIFT_BUILD_DIR/MacSVNFinderSync"
RUST_EXECUTABLE="$RUST_BUILD_DIR/mtsvn-rs"
ICONSET_DIR="$DIST_DIR/$APP_NAME.iconset"
ICON_FILE="$DIST_DIR/$APP_NAME.icns"
LOGO_SOURCE="$ROOT_DIR/Sources/MacSVNWorkbench/Resources/tmsTUCenter.jpg"

if [[ -n "${MACSVN_CODESIGN_IDENTITY:-}" ]]; then
    CODESIGN_IDENTITY="$MACSVN_CODESIGN_IDENTITY"
else
    CODESIGN_IDENTITY="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | awk -F'"' '/Apple Development:/ { print $2; exit }'
    )"
    if [[ -z "$CODESIGN_IDENTITY" ]]; then
        CODESIGN_IDENTITY="-"
    fi
fi

mkdir -p "$BUILD_HOME" "$MODULE_CACHE" "$DIST_DIR"

env \
    HOME="$BUILD_HOME" \
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
    swift build --product "$APP_NAME"

env \
    HOME="$BUILD_HOME" \
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
    swift build --product MacSVNStatusXPCService

env \
    HOME="$BUILD_HOME" \
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
    swift build --product MacSVNFinderSync

(
    cd "$ROOT_DIR/rust"
    /opt/homebrew/bin/cargo build -q -p mtsvn-rs
)

rm -rf \
    "$APP_BUNDLE" \
    "$DIST_DIR/$LEGACY_APP_NAME.app" \
    "$ICONSET_DIR" \
    "$DIST_DIR/$LEGACY_APP_NAME.iconset" \
    "$ICON_FILE" \
    "$DIST_DIR/$LEGACY_APP_NAME.icns"

mkdir -p \
    "$APP_BUNDLE/Contents/MacOS" \
    "$APP_BUNDLE/Contents/Resources/bin" \
    "$APP_BUNDLE/Contents/PlugIns" \
    "$APP_BUNDLE/Contents/XPCServices" \
    "$FINDER_BUNDLE/Contents/MacOS" \
    "$XPC_BUNDLE/Contents/MacOS" \
    "$XPC_BUNDLE/Contents/Resources/bin"

cp "$APP_INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
cp "$WORKBENCH_EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp -R "$WORKBENCH_RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
cp "$RUST_EXECUTABLE" "$APP_BUNDLE/Contents/Resources/bin/mtsvn-rs"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME" "$APP_BUNDLE/Contents/Resources/bin/mtsvn-rs"

mkdir -p "$ICONSET_DIR"
for size in 16 32 128 256 512; do
    retina_size=$((size * 2))
    sips -s format png -z "$size" "$size" "$LOGO_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    sips -s format png -z "$retina_size" "$retina_size" "$LOGO_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/$APP_NAME.icns"

cp "$FINDER_INFO_PLIST" "$FINDER_BUNDLE/Contents/Info.plist"
cp "$FINDER_EXECUTABLE" "$FINDER_BUNDLE/Contents/MacOS/MacSVNFinderSync"
chmod +x "$FINDER_BUNDLE/Contents/MacOS/MacSVNFinderSync"

cp "$XPC_INFO_PLIST" "$XPC_BUNDLE/Contents/Info.plist"
cp "$XPC_EXECUTABLE" "$XPC_BUNDLE/Contents/MacOS/MacSVNStatusXPCService"
cp "$RUST_EXECUTABLE" "$XPC_BUNDLE/Contents/Resources/bin/mtsvn-rs"
chmod +x \
    "$XPC_BUNDLE/Contents/MacOS/MacSVNStatusXPCService" \
    "$XPC_BUNDLE/Contents/Resources/bin/mtsvn-rs"

/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE/Contents/Resources/bin/mtsvn-rs"
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" "$XPC_BUNDLE/Contents/Resources/bin/mtsvn-rs"
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --generate-entitlement-der --entitlements "$FINDER_ENTITLEMENTS" "$FINDER_BUNDLE/Contents/MacOS/MacSVNFinderSync"
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --preserve-metadata=entitlements "$FINDER_BUNDLE"
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" "$XPC_BUNDLE"
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --generate-entitlement-der --entitlements "$APP_ENTITLEMENTS" "$APP_BUNDLE"
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --generate-entitlement-der --entitlements "$FINDER_ENTITLEMENTS" "$FINDER_BUNDLE/Contents/MacOS/MacSVNFinderSync"
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --preserve-metadata=entitlements "$FINDER_BUNDLE"

echo "Built app bundle:"
echo "$APP_BUNDLE"
