#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"
"$PROJECT_ROOT/Scripts/swift.sh" build --product PeerJetty -Xswiftc -enable-testing
BIN_DIR="$("$PROJECT_ROOT/Scripts/swift.sh" build --show-bin-path)"
TEST_ROOT="$(mktemp -d /private/tmp/PeerJetty-disk-tests.XXXXXX)"
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
# Standalone Network.framework checks use ephemeral identities and temporary storage.
/usr/bin/swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" \
  -module-cache-path "$PROJECT_ROOT/.module-cache" \
  -I "$BIN_DIR" -I "$BIN_DIR/Modules" "${CORE_OBJECTS[@]}" \
  Tests/DiskSpaceTests/DiskSpaceTests.swift -o "$TEST_ROOT/tests"
"$TEST_ROOT/tests" "$@"
