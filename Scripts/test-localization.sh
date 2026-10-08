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
# Standalone AppKit checks work with Command Line Tools, without XCTest/Xcode.
/usr/bin/swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" \
  -module-cache-path "$PROJECT_ROOT/.module-cache" \
  -I "$BIN_DIR" -I "$BIN_DIR/Modules" "${CORE_OBJECTS[@]}" \
  Sources/PeerJetty/Motion.swift Sources/PeerJetty/Settings.swift Sources/PeerJetty/AppVersion.swift \
  Tests/LocalizationTests/LocalizationTests.swift -o "$TEST_ROOT/tests"
TEST_EXECUTABLE="$TEST_ROOT/tests"
if [[ "${1:-}" == --app ]]; then
  APP_UNDER_TEST="$2"
  TEST_APP="$TEST_ROOT/Relocated.app"
  mkdir -p "$TEST_APP/Contents/MacOS"
  cp "$TEST_ROOT/tests" "$TEST_APP/Contents/MacOS/checks"
  /usr/bin/ditto "$APP_UNDER_TEST/Contents/Resources" "$TEST_APP/Contents/Resources"
  /usr/bin/python3 - "$APP_UNDER_TEST/Contents/Info.plist" "$TEST_APP/Contents/Info.plist" <<'PYINFO'
import sys, plistlib
from pathlib import Path
info = plistlib.loads(Path(sys.argv[1]).read_bytes())
info['CFBundleExecutable'] = 'checks'
info['CFBundleIdentifier'] = 'app.peerjetty.localization-checks'
Path(sys.argv[2]).write_bytes(plistlib.dumps(info))
PYINFO
  TEST_EXECUTABLE="$TEST_APP/Contents/MacOS/checks"
fi
"$TEST_EXECUTABLE" "$@"
