#!/usr/bin/env python3
"""Embed/sign the pinned Sparkle binary; preserve symlinks and helpers."""
from pathlib import Path
import os, subprocess, sys
root=Path(__file__).resolve().parents[1]
app=Path(sys.argv[1])
source=root/'.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
if not source.exists(): raise SystemExit('Build the pinned Sparkle package first')
target=app/'Contents/Frameworks/Sparkle.framework';target.parent.mkdir(parents=True,exist_ok=True)
subprocess.run(['/usr/bin/ditto',str(source),str(target)],check=True)
license=root/'.build/checkouts/Sparkle/LICENSE'
if not license.exists(): license=root/'.build/checkouts/sparkle/LICENSE'
subprocess.run(['/bin/cp',str(license),str(app/'Contents/Resources/Sparkle-LICENSE')],check=True)
(app/'Contents/Resources/Sparkle-LICENSE').chmod(0o644)
identity=os.environ.get('PEERJETTY_SIGNING_IDENTITY') or os.environ.get('OPENONMINI_SIGNING_IDENTITY') or '-'
options=['--options','runtime','--timestamp'] if identity != '-' else []
# Sign actual nested executables, then owning bundles, then the outer framework.
version=target/'Versions/B'
magic={b'\xcf\xfa\xed\xfe',b'\xce\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xca\xfe\xba\xbf'}
for path in sorted(version.rglob('*')):
    if path.is_symlink() or not path.is_file():continue
    with path.open('rb') as f: header=f.read(4)
    if header in magic:subprocess.run(['/usr/bin/codesign','--force',*options,'--sign',identity,str(path)],check=True)
for bundle in sorted([p for p in version.rglob('*') if p.suffix in ('.app','.xpc') and p.is_dir()],key=lambda p:len(p.parts),reverse=True):
    subprocess.run(['/usr/bin/codesign','--force',*options,'--sign',identity,str(bundle)],check=True)
subprocess.run(['/usr/bin/codesign','--force',*options,'--sign',identity,str(target)],check=True)
subprocess.run(['/usr/bin/codesign','--verify','--strict','--deep',str(target)],check=True)
