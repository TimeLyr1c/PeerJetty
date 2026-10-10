import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('check_app_privacy', Path(__file__).resolve().parents[2] / 'Scripts/check_app_privacy.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class AppPrivacyTests(unittest.TestCase):
    def test_release_private_material_and_compatibility_identifiers(self):
        with tempfile.TemporaryDirectory() as root:
            app = Path(root) / 'PeerJetty.app'
            binary = app / 'Contents/MacOS/PeerJetty'
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'app.openonmini.desktop 127.0.0.1')
            self.assertEqual(module.audit(app), [])
            for data in (b'/Users/fictional/Developer/', b'-----BEGIN PRIVATE KEY-----', b'ghp_' + b'x' * 36):
                binary.write_bytes(data)
                self.assertTrue(module.audit(app))
            binary.write_bytes(b'clean')
            (app / 'history.sqlite').write_bytes(b'fixture')
            self.assertTrue(module.audit(app))

if __name__ == '__main__':
    unittest.main()
