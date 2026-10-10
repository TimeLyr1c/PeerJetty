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
    executable = app / 'Contents/MacOS/PeerJetty'
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
    app = ROOT / 'outputs/PeerJetty.app'
    metadata = json.loads((app / 'Contents/Resources/build-info.json').read_text())
    if git_state() != (revision, False) or metadata['git_commit'] != revision or metadata['dirty']:
        raise ValueError('Source changed during build; no archive created')
    if (metadata['product_version'], metadata['build_number']) != (source['CFBundleShortVersionString'], source['CFBundleVersion']):
        raise ValueError('Version changed during build; no archive created')
    destination.mkdir(parents=True, exist_ok=True)
    staged = Path(tempfile.mkdtemp(prefix='.PeerJetty-', dir=str(destination)))
    try:
        architecture = '-'.join(metadata['architectures'])
        filename = 'PeerJetty-{}-{}.zip'.format(label, architecture)
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
            '# PeerJetty {}\n\n'.format(label) +
            '- Source commit: `{}`\n'.format(revision) +
            '- Configuration: release; architectures: {}\n'.format(architecture) +
            '- Build time (UTC): {}\n'.format(metadata['built_at_utc']) +
            '- Signing: {}\n'.format(metadata['signing']) +
            '- Notarization: not performed by this tool\n' +
            '- Validation: compilation and signature verification passed. Physical two-Mac acceptance is pending for this package.\n' +
            '- Distribution: local candidate; packaging does not upload to GitHub or establish redistribution permission.\n\n' +
            'Detailed toolchain and source provenance: build-info.json.\n')
        disk_image(staged)
        # A single publisher may create a given archive; never replace an existing one.
        if target.exists():
            raise ValueError('Another package already created this archive')
        os.rename(staged, target)
        print(target)
    finally:
        if staged.exists():
            shutil.rmtree(staged)


def disk_image(archive):
    """Add a new installer container around an already verified ZIP; never rebuild its app."""
    archive = archive.expanduser().resolve()
    metadata = json.loads((archive / 'build-info.json').read_text())
    version, build = metadata['product_version'], metadata['build_number']
    architectures = metadata['architectures']
    if (not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version)
            or not re.fullmatch(r'[0-9]+', build)
            or not architectures or any(x not in ('arm64', 'x86_64') for x in architectures)
            or metadata['dirty']):
        raise ValueError('Invalid or uncommitted archived build')
    stem = 'PeerJetty-{}-build{}-{}'.format(version, build, '-'.join(architectures))
    zipped = archive / (stem + '.zip')
    image = archive / (stem + '.dmg')
    checksum = archive / 'SHA256SUMS-DMG.txt'
    if image.exists() or checksum.exists():
        raise ValueError('DMG or its checksum already exists; never overwrite an installer')
    expected = '{}  {}\n'.format(hashlib.sha256(zipped.read_bytes()).hexdigest(), zipped.name)
    if (archive / 'SHA256SUMS.txt').read_text() != expected:
        raise ValueError('Archived ZIP does not match its checksum')
    with tempfile.TemporaryDirectory(prefix='PeerJetty-dmg-') as directory:
        scratch = Path(directory)
        extracted = scratch / 'extracted'
        subprocess.run(['/usr/bin/ditto', '-x', '-k', str(zipped), str(extracted)], check=True)
        app = extracted / 'PeerJetty.app'
        bundled = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        provenance = json.loads((app / 'Contents/Resources/build-info.json').read_text())
        if ((bundled['CFBundleShortVersionString'], bundled['CFBundleVersion']) != (version, build)
                or provenance['git_commit'] != metadata['git_commit'] or provenance['dirty']):
            raise ValueError('Archived application and build metadata disagree')
        subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(app)], check=True)
        content = scratch / 'content'
        content.mkdir()
        subprocess.run(['/usr/bin/ditto', '--noextattr', '--noqtn', str(app), str(content / app.name)], check=True)
        (content / 'Applications').symlink_to('/Applications', target_is_directory=True)
        (content / 'INSTALL.txt').write_text(
            'PeerJetty {} / build {}\n\n'.format(version, build) +
            'Drag PeerJetty.app to Applications, then eject this disk image.\n'
            'Quit an older PeerJetty before replacing it. Run the app from Applications.\n'
            'macOS 15+. See the architecture in this installer filename.\n'
            'This build is ad hoc signed, not notarized.\n'
            'This is a menu bar app; open Settings from its menu bar icon.\n'
            'Source and instructions: https://github.com/TimeLyr1c/PeerJetty\n\n'
            '安装：退出旧版，将 PeerJetty.app 拖入 Applications 后推出镜像，再从应用程序打开。\n'
            '支持 macOS 15+，架构见安装包名称。采用 ad hoc 签名，尚未经过 Apple 公证。\n'
            '默认在菜单栏运行，从菜单打开设置。\n')
        staged = scratch / image.name
        subprocess.run(['/usr/bin/hdiutil', 'create', '-volname', 'PeerJetty', '-fs', 'HFS+',
                        '-srcfolder', str(content), '-format', 'UDZO', str(staged)], check=True)
        subprocess.run(['/usr/bin/hdiutil', 'verify', str(staged)], check=True)
        # Exclusive final file creation also protects against simultaneous publishers.
        with image.open('xb') as output, staged.open('rb') as source:
            shutil.copyfileobj(source, output)
        digest = hashlib.sha256(image.read_bytes()).hexdigest()
        with checksum.open('x') as output:
            output.write('{}  {}\n'.format(digest, image.name))
        print(image)


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
    installer = sub.add_parser('dmg')
    installer.add_argument('archive', type=Path, help='Existing version-build ZIP archive directory')
    args = parser.parse_args()
    try:
        if args.command == 'show':
            print('{} / build {}'.format(info()['CFBundleShortVersionString'], info()['CFBundleVersion']))
        elif args.command == 'set':
            set_version(args.version, args.build)
        elif args.command == 'stamp':
            stamp(args.app, args.configuration)
        elif args.command == 'dmg':
            disk_image(args.archive)
        else:
            package(args.destination)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
