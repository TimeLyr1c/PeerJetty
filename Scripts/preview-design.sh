#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"
# Freeze the previous native refinement source. Never switch or alter the live checkout.
BASELINE_REF=95ac75a
./Scripts/swift.sh build --product PeerJetty -Xswiftc -enable-testing
BIN_DIR="$(./Scripts/swift.sh build --show-bin-path)"
TEST_ROOT="$(mktemp -d /private/tmp/PeerJetty-design-preview.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT
if [[ -f "$BIN_DIR/PeerCore.o" ]]; then
  CORE_OBJECTS=("$BIN_DIR/PeerCore.o")
else
  CORE_OBJECTS=("$BIN_DIR/PeerCore.build/"*.o(N))
fi
PREVIEW_ROOT="$PROJECT_ROOT/outputs/previews/design-build21"
for SIDE in Before After; do
  SOURCES=()
  for FILE in Motion Settings AppVersion DropPresentation DropZone; do
    if [[ "$SIDE" == Before ]]; then
      git show "$BASELINE_REF:Sources/PeerJetty/$FILE.swift" > "$TEST_ROOT/$FILE.swift"
      SOURCES+=("$TEST_ROOT/$FILE.swift")
    else
      SOURCES+=("Sources/PeerJetty/$FILE.swift")
    fi
  done
  APP="$PREVIEW_ROOT/$SIDE.app"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  /usr/bin/swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" -module-cache-path .module-cache -I "$BIN_DIR" -I "$BIN_DIR/Modules" "${CORE_OBJECTS[@]}" "${SOURCES[@]}" Tests/DesignPreview/DesignPreview.swift -o "$APP/Contents/MacOS/Preview"
  /usr/bin/ditto "$BIN_DIR/PeerJetty_PeerCore.bundle" "$APP/Contents/Resources/PeerJetty_PeerCore.bundle"
  /usr/bin/ditto Sources/PeerCore/Resources "$APP/Contents/Resources"
  cp LICENSE "$APP/Contents/Resources/LICENSE"
  cp Assets/AppIcon.png "$APP/Contents/Resources/AppIcon.png"
  /usr/bin/python3 - "$APP/Contents/Info.plist" "$SIDE" <<'PY'
import plistlib,sys
from pathlib import Path
side=sys.argv[2]
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleExecutable':'Preview','CFBundleIdentifier':'app.peerjetty.design-preview.'+side.lower(),'CFBundleName':'PeerJetty Design '+side,'PJComparisonSide':side,'CFBundleShortVersionString':'0.4.0','CFBundleVersion':'20' if side == 'Before' else '21','LSMinimumSystemVersion':'15.0','NSHighResolutionCapable':True,'CFBundleIconFile':'AppIcon.png'}))
PY
  /usr/bin/codesign --force --sign - "$APP"
done
print "$PREVIEW_ROOT/After.app"
