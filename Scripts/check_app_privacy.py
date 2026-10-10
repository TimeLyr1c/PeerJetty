#!/usr/bin/env python3
"""Fail closed on common private material in an assembled public App."""
from pathlib import Path
import re
import sys

PATTERNS = {
    "personal home path": rb"/Users/[^/\x00\s]+/|[A-Z]:\\Users\\",
    "private key": rb"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----",
    "known credential": rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|AKIA[A-Z0-9]{16})",
}

def audit(app):
    if not (app / 'Contents/MacOS/PeerJetty').is_file():
        raise ValueError('Missing assembled executable')
    findings = []
    for path in app.rglob('*'):
        if not path.is_file():
            continue
        relative = str(path.relative_to(app))
        if path.suffix.lower() in ('.sqlite', '.sqlite3', '.pem', '.key', '.p12'):
            findings.append((relative, 'private runtime file'))
        data = path.read_bytes()
        for name, pattern in PATTERNS.items():
            if re.search(pattern, data):
                findings.append((relative, name))
    return findings

if __name__ == '__main__':
    findings = audit(Path(sys.argv[1]))
    for path, kind in findings:
        print(f'Privacy check failed: {path}: {kind}', file=sys.stderr)
    if findings:
        sys.exit(1)
    print('Assembled App privacy pattern check passed')
