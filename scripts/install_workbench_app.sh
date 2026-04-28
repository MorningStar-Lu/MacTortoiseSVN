#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/build_workbench_app.sh"
APP_SOURCE="$ROOT_DIR/dist/MacTortoiseSVN.app"
APP_TARGET="/Applications/MacTortoiseSVN.app"
APP_BUNDLE_ID="com.morningstar.MacTortoiseSVN"
LEGACY_APP_TARGET="/Applications/MacSVNWorkbench.app"
LEGACY_APP_BUNDLE_ID="com.morningstar.MacTortoiseSVN.Workbench"
APP_ENTITLEMENTS="$ROOT_DIR/Apps/MacSVNApp/MacSVNWorkbench.entitlements"
FINDER_EXTENSION_ID="com.morningstar.MacTortoiseSVN.FinderSync"
FINDER_EXTENSION_PATH="$APP_TARGET/Contents/PlugIns/$FINDER_EXTENSION_ID.appex"
FINDER_EXTENSION_EXECUTABLE="$FINDER_EXTENSION_PATH/Contents/MacOS/MacSVNFinderSync"
FINDER_ENTITLEMENTS="$ROOT_DIR/Apps/MacSVNFinderSync/MacSVNFinderSync.entitlements"

if [[ -n "${MACSVN_CODESIGN_IDENTITY:-}" ]]; then
    CODESIGN_IDENTITY="$MACSVN_CODESIGN_IDENTITY"
else
    CODESIGN_IDENTITY="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | awk -F'"' '/Apple Development:/ { print $2; exit }'
    )"
fi

if [[ ! -x "$BUILD_SCRIPT" ]]; then
    echo "Missing build script: $BUILD_SCRIPT" >&2
    exit 1
fi

"$BUILD_SCRIPT"

if [[ ! -d "$APP_SOURCE" ]]; then
    echo "Missing app bundle: $APP_SOURCE" >&2
    exit 1
fi

/usr/bin/osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
/usr/bin/osascript -e "tell application id \"$LEGACY_APP_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
for _ in {1..20}; do
    if ! /usr/bin/pgrep -x "MacTortoiseSVN" >/dev/null 2>&1 \
        && ! /usr/bin/pgrep -x "MacSVNWorkbench" >/dev/null 2>&1; then
        break
    fi
    /bin/sleep 0.2
done
/usr/bin/pkill -x "MacTortoiseSVN" >/dev/null 2>&1 || true
/usr/bin/pkill -x "MacSVNWorkbench" >/dev/null 2>&1 || true
/usr/bin/pkill -x "MacSVNStatusXPCService" >/dev/null 2>&1 || true
/usr/bin/pkill -f "/Applications/MacTortoiseSVN.app/Contents/.*/mtsvn-rs" >/dev/null 2>&1 || true
/usr/bin/pkill -f "/Applications/MacSVNWorkbench.app/Contents/.*/mtsvn-rs" >/dev/null 2>&1 || true

/bin/rm -rf "$LEGACY_APP_TARGET"
/usr/bin/ditto "$APP_SOURCE" "$APP_TARGET"
/usr/bin/xattr -dr com.apple.quarantine "$APP_TARGET" || true

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    /usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --generate-entitlement-der --entitlements "$FINDER_ENTITLEMENTS" "$FINDER_EXTENSION_EXECUTABLE"
    /usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --preserve-metadata=entitlements "$FINDER_EXTENSION_PATH"
    /usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --generate-entitlement-der --entitlements "$APP_ENTITLEMENTS" "$APP_TARGET"
fi

/usr/bin/open -a "$APP_TARGET"
/usr/bin/pluginkit -a "$FINDER_EXTENSION_PATH" || true
/usr/bin/pluginkit -e use -i "$FINDER_EXTENSION_ID" || true

echo "Installed app:"
echo "$APP_TARGET"
echo
echo "If the Finder menu still does not appear, toggle the extension in:"
echo "System Settings > Privacy & Security > Extensions > Finder Extensions"
