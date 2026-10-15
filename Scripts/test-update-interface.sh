#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"
"$PROJECT_ROOT/Scripts/swift.sh" build --product PeerJetty
BIN_DIR="$("$PROJECT_ROOT/Scripts/swift.sh" build --show-bin-path)"
TEST_ROOT="$(mktemp -d /private/tmp/PeerJetty-update-ui.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT
FRAMEWORK="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
if [[ -f "$BIN_DIR/PeerCore.o" ]]; then
 CORE_OBJECTS=("$BIN_DIR/PeerCore.o")
else
 CORE_OBJECTS=("$BIN_DIR/PeerCore.build/"*.o(N))
fi
APP="$TEST_ROOT/Checks.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
/usr/bin/ditto "$FRAMEWORK/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
for lang in en zh-Hans; do
 /usr/bin/ditto "$PROJECT_ROOT/Sources/PeerCore/Resources/$lang.lproj" "$APP/Contents/Resources/$lang.lproj"
done
/usr/bin/python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib,sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleIdentifier':'app.peerjetty.test.update-ui','CFBundleName':'Update UI Checks','CFBundleExecutable':'checks','CFBundleVersion':'1','CFBundleLocalizations':['en','zh-Hans'],'CFBundleDevelopmentRegion':'en'}))
PY
/usr/bin/swiftc -parse-as-library -module-cache-path "$PROJECT_ROOT/.module-cache" -I "$BIN_DIR" -I "$BIN_DIR/Modules" -F "$FRAMEWORK" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks "${CORE_OBJECTS[@]}" Sources/PeerJetty/InAppUpdater.swift Tests/UpdateInterfaceTests/UpdateInterfaceTests.swift -o "$APP/Contents/MacOS/checks"
"$APP/Contents/MacOS/checks" -AppleLanguages '(en)'
"$APP/Contents/MacOS/checks" -AppleLanguages '(zh-Hans)'

"$APP/Contents/MacOS/checks" --seed-language
"$APP/Contents/MacOS/checks"
