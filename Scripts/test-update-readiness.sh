#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"
"$PROJECT_ROOT/Scripts/swift.sh" build --product PeerJetty
BIN_DIR="$("$PROJECT_ROOT/Scripts/swift.sh" build --show-bin-path)"
TEST_ROOT="$(mktemp -d /private/tmp/PeerJetty-readiness.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT
FRAMEWORK="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
if [[ -f "$BIN_DIR/PeerCore.o" ]]; then
 CORE_OBJECTS=("$BIN_DIR/PeerCore.o")
else
 CORE_OBJECTS=("$BIN_DIR/PeerCore.build/"*.o(N))
fi
APP="$TEST_ROOT/Checks.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
/usr/bin/ditto Sources/PeerCore/Resources "$APP/Contents/Resources"
/usr/bin/ditto "$FRAMEWORK/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
/usr/bin/ditto "$BIN_DIR/PeerJetty_PeerCore.bundle" "$TEST_ROOT/PeerJetty_PeerCore.bundle"
/usr/bin/python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib,sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleIdentifier':'app.peerjetty.test.readiness','CFBundleExecutable':'checks','CFBundleVersion':'1','LSUIElement':True}))
PY
/usr/bin/swiftc -D PEERJETTY_TESTING -parse-as-library -module-cache-path "$PROJECT_ROOT/.module-cache" -I "$BIN_DIR" -I "$BIN_DIR/Modules" -F "$FRAMEWORK" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks "${CORE_OBJECTS[@]}" Sources/PeerJetty/*.swift Tests/UpdateReadinessTests/UpdateReadinessTests.swift -o "$APP/Contents/MacOS/checks"
"$APP/Contents/MacOS/checks" "$TEST_ROOT" "$@"
