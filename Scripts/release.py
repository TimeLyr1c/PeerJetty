#!/usr/bin/env python3
"""Version, build provenance, and immutable local package archives."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True, stderr=subprocess.PIPE).strip()


def git_state():
    return run('git', 'rev-parse', 'HEAD'), bool(run('git', 'status', '--porcelain'))


def info():
    return plistlib.loads((ROOT / 'Info.plist').read_bytes())


def stamp(app, configuration):
    executable = app / 'Contents/MacOS/OpenOnMini'
    revision, dirty = git_state()
    metadata = {
        'product_version': info()['CFBundleShortVersionString'],
        'build_number': info()['CFBundleVersion'],
        'git_commit': revision,
        'dirty': dirty,
        'configuration': configuration,
        'architectures': run('/usr/bin/lipo', '-archs', str(executable)).split(),
        'built_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'macos_version': run('/usr/bin/sw_vers', '-productVersion'),
        'swift_version': run('/usr/bin/swift', '--version'),
        'sdk_version': run('/usr/bin/xcrun', '--show-sdk-version'),
    }
    path = app / 'Contents/Resources/build-info.json'
    path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')


def set_version(version, build):
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version):
        raise ValueError('Version must be three numbers, for example 0.2.1')
    current = info()
    if build <= int(current['CFBundleVersion']):
        raise ValueError('A new delivery must have a higher build number')
    if tuple(map(int, version.split('.'))) < tuple(map(int, current['CFBundleShortVersionString'].split('.'))):
        raise ValueError('Product version cannot move backwards')
    current['CFBundleShortVersionString'] = version
    current['CFBundleVersion'] = str(build)
    (ROOT / 'Info.plist').write_bytes(plistlib.dumps(current, sort_keys=False))
    print('Version {} / build {} set; review and commit before packaging.'.format(version, build))


def package(destination):
    revision, dirty = git_state()
    if dirty:
        raise ValueError('Save all intended source and documentation in Git before packaging; repository is not clean')
    source = info()
    label = '{}-build{}'.format(source['CFBundleShortVersionString'], source['CFBundleVersion'])
    destination = destination.expanduser().resolve()
    target = destination / label
    if target.exists():
        raise ValueError('Archive already exists; increase the build number instead of overwriting: ' + str(target))
    subprocess.run([str(ROOT / 'build.sh'), 'release'], cwd=ROOT, check=True)
    app = ROOT / 'outputs/OpenOnMini.app'
    metadata = json.loads((app / 'Contents/Resources/build-info.json').read_text())
    if git_state() != (revision, False) or metadata['git_commit'] != revision or metadata['dirty']:
        raise ValueError('Source changed during build; no archive created')
    if (metadata['product_version'], metadata['build_number']) != (source['CFBundleShortVersionString'], source['CFBundleVersion']):
        raise ValueError('Version changed during build; no archive created')
    destination.mkdir(parents=True, exist_ok=True)
    staged = Path(tempfile.mkdtemp(prefix='.OpenOnMini-', dir=str(destination)))
    try:
        architecture = '-'.join(metadata['architectures'])
        filename = 'OpenOnMini-{}-{}.zip'.format(label, architecture)
        subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(app)], check=True)
        subprocess.run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent',
                        str(app), str(staged / filename)], check=True)
        signing = subprocess.run(['/usr/bin/codesign', '-d', '--verbose=2', str(app)],
                                 capture_output=True, text=True, check=True).stderr
        metadata['signing'] = 'ad hoc' if 'Signature=adhoc' in signing else 'signed; see signature.txt'
        metadata['notarization'] = 'Not performed by this packaging tool'
        public_signature = '\n'.join(line for line in signing.splitlines() if line.startswith(
            ('Identifier=', 'Format=', 'CodeDirectory', 'Signature=', 'Authority=', 'TeamIdentifier=', 'Timestamp=')))
        (staged / 'signature.txt').write_text(public_signature + '\n')
        (staged / 'build-info.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
        checksum = hashlib.sha256((staged / filename).read_bytes()).hexdigest()
        (staged / 'SHA256SUMS.txt').write_text('{}  {}\n'.format(checksum, filename))
        (staged / 'release-info.md').write_text(
            '# OpenOnMini {}\n\n'.format(label) +
            '- Source commit: `{}`\n'.format(revision) +
            '- Configuration: release; architectures: {}\n'.format(architecture) +
            '- Build time (UTC): {}\n'.format(metadata['built_at_utc']) +
            '- Signing: {}\n'.format(metadata['signing']) +
            '- Notarization: not performed by this tool\n' +
            '- Validation: compilation and signature verification passed. Physical two-Mac acceptance is pending for this package.\n' +
            '- Distribution: local candidate; packaging does not upload to GitHub or establish redistribution permission.\n\n' +
            'Detailed toolchain and source provenance: build-info.json.\n')
        # A single publisher may create a given archive; never replace an existing one.
        if target.exists():
            raise ValueError('Another package already created this archive')
        os.rename(staged, target)
        print(target)
    finally:
        if staged.exists():
            shutil.rmtree(staged)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('show')
    version = sub.add_parser('set')
    version.add_argument('version')
    version.add_argument('--build', type=int, required=True)
    stamping = sub.add_parser('stamp')
    stamping.add_argument('app', type=Path)
    stamping.add_argument('configuration', choices=['debug', 'release'])
    packaging = sub.add_parser('package')
    packaging.add_argument('--destination', type=Path, default=ROOT / 'outputs/releases')
    args = parser.parse_args()
    try:
        if args.command == 'show':
            print('{} / build {}'.format(info()['CFBundleShortVersionString'], info()['CFBundleVersion']))
        elif args.command == 'set':
            set_version(args.version, args.build)
        elif args.command == 'stamp':
            stamp(args.app, args.configuration)
        else:
            package(args.destination)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
