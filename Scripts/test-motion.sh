#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"
./Scripts/swift.sh build --product PeerJetty -Xswiftc -enable-testing
BIN_DIR="$(./Scripts/swift.sh build --show-bin-path)"
TEST_ROOT="$(mktemp -d /private/tmp/PeerJetty-motion-tests.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT
/usr/bin/ditto "$BIN_DIR/PeerJetty_PeerCore.bundle" "$TEST_ROOT/PeerJetty_PeerCore.bundle"
if [[ -f "$BIN_DIR/PeerCore.o" ]]; then
  CORE_OBJECTS=("$BIN_DIR/PeerCore.o")
else
  CORE_OBJECTS=("$BIN_DIR/PeerCore.build/"*.o(N))
fi
SOURCES=(Sources/PeerJetty/Motion.swift Sources/PeerJetty/DropPresentation.swift Sources/PeerJetty/DropZone.swift Sources/PeerJetty/TextWindows.swift Tests/MotionTests/MotionTests.swift)
/usr/bin/swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" -module-cache-path .module-cache -I "$BIN_DIR" -I "$BIN_DIR/Modules" "${CORE_OBJECTS[@]}" "${SOURCES[@]}" -o "$TEST_ROOT/checks"
"$TEST_ROOT/checks" "$@"
if [[ "${1:-}" == --deliver-preview ]]; then
  APP="$PROJECT_ROOT/outputs/GlassMotionPreview.app"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$TEST_ROOT/checks" "$APP/Contents/MacOS/Preview"
  /usr/bin/ditto Sources/PeerCore/Resources "$APP/Contents/Resources"
  /usr/bin/python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib,sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleExecutable':'Preview','CFBundleIdentifier':'app.peerjetty.isolated-glass-preview','CFBundleName':'PeerJetty UI Preview','LSMinimumSystemVersion':'15.0','NSHighResolutionCapable':True}))
PY
  /usr/bin/codesign --force --sign - "$APP"
  print "$APP"
fi
if [[ "${1:-}" == --compare ]]; then
  # Read the pre-change card from HEAD into temporary files; never switch the live checkout.
  git show "${PEERJETTY_MOTION_BASELINE_REF:-630a44172aeb82a498fd39e6d812eb7ebc9d464a}:Sources/PeerJetty/DropZone.swift" > "$TEST_ROOT/LegacyDropZone.swift"
  /usr/bin/swiftc -D BASELINE -parse-as-library -target "$(uname -m)-apple-macos15.0" -module-cache-path .module-cache -I "$BIN_DIR" -I "$BIN_DIR/Modules" "${CORE_OBJECTS[@]}" Sources/PeerJetty/DropPresentation.swift "$TEST_ROOT/LegacyDropZone.swift" Tests/MotionTests/MotionTests.swift -o "$TEST_ROOT/baseline"
  print 'Before (old material, no custom status animation):'
  "$TEST_ROOT/baseline" --benchmark
  print 'After (native glass, custom status animation):'
  "$TEST_ROOT/checks" --benchmark
fi
