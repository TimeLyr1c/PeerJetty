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
if [[ "${1:-}" == --compare ]]; then
  # Read the pre-change card from HEAD into temporary files; never switch the live checkout.
  BASELINE_REF="${PEERJETTY_MOTION_BASELINE_REF:-52a341573cd2b317d34606a8edf674382e0982b2}"
  git show "$BASELINE_REF:Sources/PeerJetty/DropZone.swift" > "$TEST_ROOT/LegacyDropZone.swift"
  BASELINE_SOURCES=()
  BASELINE_FLAGS=(-D BASELINE)
  if git cat-file -e "$BASELINE_REF:Sources/PeerJetty/Motion.swift" 2>/dev/null; then
    git show "$BASELINE_REF:Sources/PeerJetty/Motion.swift" > "$TEST_ROOT/LegacyMotion.swift"
    BASELINE_SOURCES+=("$TEST_ROOT/LegacyMotion.swift")
  fi
  if rg -q 'final class DropCardHost' "$TEST_ROOT/LegacyDropZone.swift"; then
    BASELINE_FLAGS+=(-D HOST_BASELINE)
  fi
  /usr/bin/swiftc "${BASELINE_FLAGS[@]}" -parse-as-library -target "$(uname -m)-apple-macos15.0" -module-cache-path .module-cache -I "$BIN_DIR" -I "$BIN_DIR/Modules" "${CORE_OBJECTS[@]}" "${BASELINE_SOURCES[@]}" Sources/PeerJetty/DropPresentation.swift "$TEST_ROOT/LegacyDropZone.swift" Tests/MotionTests/MotionTests.swift -o "$TEST_ROOT/baseline"
  print 'Before (build16 glass card and bar progress):'
  "$TEST_ROOT/baseline" --benchmark
  print 'After (three speeds and vector progress/check):'
  "$TEST_ROOT/checks" --benchmark
fi
