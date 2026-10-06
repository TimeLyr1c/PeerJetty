import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release_tools', Path(__file__).resolve().parents[2] / 'Scripts/release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.override = patch.object(release, 'ROOT', self.root)
        self.override.start()
        (self.root / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleShortVersionString': '0.2.0', 'CFBundleVersion': '2'}))
        subprocess.run(['git', 'init', '-q'], cwd=self.root, check=True)
        subprocess.run(['git', 'add', 'Info.plist'], cwd=self.root, check=True)
        subprocess.run(['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                        'commit', '-qm', 'fixture'], cwd=self.root, check=True)

    def tearDown(self):
        self.override.stop()
        self.temp.cleanup()

    def test_dmg_rejects_changed_archive_before_unpacking(self):
        import json
        archive = self.root / 'archive'; archive.mkdir()
        (archive / 'build-info.json').write_text(json.dumps({
            'product_version': '0.2.4', 'build_number': '6', 'architectures': ['arm64'], 'dirty': False}))
        (archive / 'PeerJetty-0.2.4-build6-arm64.zip').write_bytes(b'changed')
        (archive / 'SHA256SUMS.txt').write_text('incorrect checksum')
        with patch.object(release.subprocess, 'run') as commands, self.assertRaises(ValueError):
            release.disk_image(archive)
        commands.assert_not_called()

    def test_dmg_does_not_overwrite_existing_installer(self):
        import json
        archive = self.root / 'archive'; archive.mkdir()
        (archive / 'build-info.json').write_text(json.dumps({
            'product_version': '0.2.4', 'build_number': '6', 'architectures': ['arm64'], 'dirty': False}))
        image = archive / 'PeerJetty-0.2.4-build6-arm64.dmg'; image.write_bytes(b'keep')
        with patch.object(release.subprocess, 'run') as commands, self.assertRaises(ValueError):
            release.disk_image(archive)
        commands.assert_not_called()
        self.assertEqual(image.read_bytes(), b'keep')

    def test_version_set_preserves_explicit_delivery_number(self):
        release.set_version('0.2.1', 3)
        self.assertEqual(release.info()['CFBundleShortVersionString'], '0.2.1')
        self.assertEqual(release.info()['CFBundleVersion'], '3')

    def test_invalid_or_backwards_version_does_not_write(self):
        before = (self.root / 'Info.plist').read_bytes()
        for version, number in [('0.1.9', 3), ('0.2.1-beta', 3), ('0.2.1', 2), ('01.2.0', 3)]:
            with self.subTest(version=version, number=number), self.assertRaises(ValueError):
                release.set_version(version, number)
        self.assertEqual((self.root / 'Info.plist').read_bytes(), before)

    def test_untracked_source_blocks_package_before_build(self):
        (self.root / 'new-source.swift').write_text('unfinished')
        with patch.object(release.subprocess, 'run', wraps=subprocess.run) as build, self.assertRaises(ValueError):
            release.package(self.root / 'archives')
        self.assertTrue(all(call.args[0][0] != str(self.root / 'build.sh') for call in build.call_args_list))

    def test_existing_archive_is_not_overwritten_or_rebuilt(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            target = destination / '0.2.0-build2'
            target.mkdir()
            marker = target / 'keep.txt'
            marker.write_text('original')
            with patch.object(release.subprocess, 'run', wraps=subprocess.run) as build, self.assertRaises(ValueError):
                release.package(destination)
            self.assertTrue(all(call.args[0][0] != str(self.root / 'build.sh') for call in build.call_args_list))
            self.assertEqual(marker.read_text(), 'original')


if __name__ == '__main__':
    unittest.main()
