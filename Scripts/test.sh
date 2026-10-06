#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
"$PROJECT_ROOT/Scripts/swift.sh" build
BIN_DIR="$("$PROJECT_ROOT/Scripts/swift.sh" build --show-bin-path)"
"$BIN_DIR/PeerTests" ${@}
"$BIN_DIR/PeerHarness" ${@}
