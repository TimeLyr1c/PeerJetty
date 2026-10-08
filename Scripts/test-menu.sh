#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"
/usr/bin/python3 "$PROJECT_ROOT/Scripts/check-localization.py"
"$PROJECT_ROOT/Scripts/swift.sh" build --product PeerJetty -Xswiftc -enable-testing
BIN_DIR="$("$PROJECT_ROOT/Scripts/swift.sh" build --show-bin-path)"
TEST_ROOT="$(mktemp -d /private/tmp/PeerJetty-localization-tests.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT
/usr/bin/ditto "$BIN_DIR/PeerJetty_PeerCore.bundle" "$TEST_ROOT/PeerJetty_PeerCore.bundle"
# Accommodate both SwiftPM's Xcode and native build-engine object layouts.
if [[ -f "$BIN_DIR/PeerCore.o" ]]; then
  CORE_OBJECTS=("$BIN_DIR/PeerCore.o")
else
  CORE_OBJECTS=("$BIN_DIR/PeerCore.build/"*.o(N))
fi
if (( ${#CORE_OBJECTS} == 0 )); then
  print -u2 'Cannot locate PeerCore build objects'; exit 1
fi
/usr/bin/swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" \
  -module-cache-path "$PROJECT_ROOT/.module-cache" \
  -I "$BIN_DIR" -I "$BIN_DIR/Modules" "${CORE_OBJECTS[@]}" \
  Sources/PeerJetty/MenuBar.swift Tests/MenuTests/MenuTests.swift -o "$TEST_ROOT/checks"
APP="$TEST_ROOT/MenuChecks.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$TEST_ROOT/checks" "$APP/Contents/MacOS/checks"
/usr/bin/ditto Sources/PeerCore/Resources "$APP/Contents/Resources"
/usr/bin/python3 - "$APP/Contents/Info.plist" <<'PYINFO'
import plistlib,sys,uuid
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleExecutable':'checks','CFBundleIdentifier':'app.peerjetty.menu-tests.'+str(uuid.uuid4()),'LSUIElement':True}))
PYINFO
"$APP/Contents/MacOS/checks" --save-hidden
"$APP/Contents/MacOS/checks" --restore-hidden
