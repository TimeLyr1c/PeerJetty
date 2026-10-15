#!/usr/bin/env python3
"""Verify the shipped executable can resolve its embedded Sparkle dependency."""
from pathlib import Path
import re
import subprocess
import sys


def rpaths(commands):
    return re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset \d+\)', commands)


def resolve_dependency(executable, dependency, search_paths):
    if not dependency.startswith('@rpath/'):
        return False
    suffix = dependency[len('@rpath/'):]
    for entry in search_paths:
        if entry.startswith('@executable_path'):
            directory = str(executable.parent) + entry[len('@executable_path'):]
        elif entry.startswith('@loader_path'):
            directory = str(executable.parent) + entry[len('@loader_path'):]
        elif entry.startswith('/'):
            directory = entry
        else:
            continue
        if (Path(directory) / suffix).is_file():
            return True
    return False


def audit(app):
    executable = app / 'Contents/MacOS/PeerJetty'
    commands = subprocess.check_output(['/usr/bin/otool', '-l', str(executable)], text=True)
    libraries = subprocess.check_output(['/usr/bin/otool', '-L', str(executable)], text=True)
    dependencies = [line.strip().split(' (')[0] for line in libraries.splitlines()[1:] if 'Sparkle.framework/' in line]
    paths = rpaths(commands)
    if len(dependencies) != 1 or '@executable_path/../Frameworks' not in paths:
        raise ValueError('Missing packaged Sparkle loader path @executable_path/../Frameworks')
    if not resolve_dependency(executable, dependencies[0], paths):
        raise ValueError('Packaged Sparkle dependency does not resolve')


if __name__ == '__main__':
    try:
        audit(Path(sys.argv[1]))
    except (ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
    print('Packaged Sparkle loader path and dependency resolution passed')
