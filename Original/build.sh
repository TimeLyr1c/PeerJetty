#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
OUTPUT_ROOT="$SCRIPT_DIR/outputs"
APP_PATH="$OUTPUT_ROOT/OpenOnMini.app"
STAGING_ROOT="$(mktemp -d /private/tmp/OpenOnMini-build.XXXXXX)"
STAGING_APP="$STAGING_ROOT/OpenOnMini.app"
trap 'rm -rf "$STAGING_ROOT"' EXIT
BUILD_APP_PATH="$STAGING_APP"
CONTENTS="$BUILD_APP_PATH/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
ICON_SOURCE="$SCRIPT_DIR/Assets/AppIcon.png"
ICONSET="$STAGING_ROOT/AppIcon.iconset"
SWIFTC="$(xcrun --find swiftc)"
SDK="$(xcrun --show-sdk-path)"
MODULE_CACHE="$SCRIPT_DIR/.module-cache"
ARCHITECTURE="$(uname -m)"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE" "$ICONSET"
cp "$SCRIPT_DIR/Info.plist" "$CONTENTS/Info.plist"
cp "$SCRIPT_DIR/PkgInfo" "$CONTENTS/PkgInfo"

sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
/usr/bin/perl "$SCRIPT_DIR/Scripts/make_icns.pl" \
    "$RESOURCES_DIR/AppIcon.icns" \
    "ic11=$ICONSET/icon_16x16@2x.png" \
    "ic12=$ICONSET/icon_32x32@2x.png" \
    "ic07=$ICONSET/icon_128x128.png" \
    "ic13=$ICONSET/icon_128x128@2x.png" \
    "ic08=$ICONSET/icon_256x256.png" \
    "ic14=$ICONSET/icon_256x256@2x.png" \
    "ic09=$ICONSET/icon_512x512.png" \
    "ic10=$ICONSET/icon_512x512@2x.png"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" "$SWIFTC" \
    -parse-as-library \
    -O \
    -target "$ARCHITECTURE-apple-macos13.0" \
    -sdk "$SDK" \
    -framework AppKit \
    -framework ServiceManagement \
    "$SCRIPT_DIR/OpenOnMini.swift" \
    -o "$MACOS_DIR/OpenOnMini"

xattr -cr "$BUILD_APP_PATH"
codesign --force --deep --sign - "$BUILD_APP_PATH"

rm -rf "$APP_PATH"
mkdir -p "$OUTPUT_ROOT"
/usr/bin/ditto --noextattr --noqtn "$BUILD_APP_PATH" "$APP_PATH"

# Finder/iCloud may attach package metadata immediately after the copy. Clear it
# and retry verification briefly so the produced app remains code-signable.
for attempt in {1..5}; do
    xattr -d com.apple.FinderInfo "$APP_PATH" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_PATH" 2>/dev/null || true

    if codesign --verify --deep --strict "$APP_PATH"; then
        break
    fi

    if (( attempt == 5 )); then
        exit 1
    fi
done

echo "$APP_PATH"
