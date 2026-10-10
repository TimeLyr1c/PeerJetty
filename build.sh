#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h}"
CONFIGURATION="${1:-release}"
if [[ "$CONFIGURATION" != release && "$CONFIGURATION" != debug ]]; then
  print -u2 'Usage: ./build.sh [release|debug]'; exit 1
fi
"$PROJECT_ROOT/Scripts/swift.sh" build -c "$CONFIGURATION" --product PeerJetty
BIN_DIR="$("$PROJECT_ROOT/Scripts/swift.sh" build -c "$CONFIGURATION" --show-bin-path)"
STAGING_ROOT="$(mktemp -d /private/tmp/PeerJetty-package.XXXXXX)"
trap 'rm -rf "$STAGING_ROOT"' EXIT
APP="$STAGING_ROOT/PeerJetty.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$STAGING_ROOT/icons"
cp "$PROJECT_ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN_DIR/PeerJetty" "$APP/Contents/MacOS/PeerJetty"
# Strip local compiler/debug paths before signing the distributed executable.
# SwiftPM retains its separate dSYM for local diagnostics.
if [[ "$CONFIGURATION" == release ]]; then
  /usr/bin/strip -S -x "$APP/Contents/MacOS/PeerJetty"
fi
for entry in 'ic11:32' 'ic12:64' 'ic07:128' 'ic13:256' 'ic08:256' 'ic14:512' 'ic09:512' 'ic10:1024'; do
  kind="${entry%%:*}"; size="${entry##*:}"
  /usr/bin/sips -z "$size" "$size" "$PROJECT_ROOT/Assets/AppIcon.png" --out "$STAGING_ROOT/icons/$kind.png" >/dev/null
done
/usr/bin/python3 "$PROJECT_ROOT/Scripts/release.py" stamp "$APP" "$CONFIGURATION"
/usr/bin/perl "$PROJECT_ROOT/Scripts/make_icns.pl" "$APP/Contents/Resources/AppIcon.icns" \
  "ic11=$STAGING_ROOT/icons/ic11.png" "ic12=$STAGING_ROOT/icons/ic12.png" "ic07=$STAGING_ROOT/icons/ic07.png" \
  "ic13=$STAGING_ROOT/icons/ic13.png" "ic08=$STAGING_ROOT/icons/ic08.png" "ic14=$STAGING_ROOT/icons/ic14.png" \
  "ic09=$STAGING_ROOT/icons/ic09.png" "ic10=$STAGING_ROOT/icons/ic10.png"
cp "$PROJECT_ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
for localization in "$PROJECT_ROOT/Sources/PeerCore/Resources/"*.lproj; do
  /usr/bin/ditto "$localization" "$APP/Contents/Resources/${localization:t}"
done
if [[ "$CONFIGURATION" == release ]]; then
  /usr/bin/python3 "$PROJECT_ROOT/Scripts/check_app_privacy.py" "$APP"
fi
/usr/bin/xattr -cr "$APP"
SIGNING_IDENTITY="${PEERJETTY_SIGNING_IDENTITY:-${OPENONMINI_SIGNING_IDENTITY:-}}"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
  /usr/bin/codesign --force --sign - "$APP"
fi
/usr/bin/codesign --verify --strict "$APP"
mkdir -p "$PROJECT_ROOT/outputs"
DESTINATION="$PROJECT_ROOT/outputs/PeerJetty.app"
if [[ -e "$DESTINATION" ]]; then rm -rf "$DESTINATION"; fi
/usr/bin/ditto --noextattr --noqtn "$APP" "$DESTINATION"
/usr/bin/codesign --verify --strict "$DESTINATION"
print "$DESTINATION"
