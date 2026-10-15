import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('check_app_linkage', Path(__file__).resolve().parents[2] / 'Scripts/check_app_linkage.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class AppLinkageTests(unittest.TestCase):
    def test_exact_packaged_layout_catches_build30_missing_rpath(self):
        commands = 'cmd LC_RPATH\n cmdsize 32\n path @loader_path (offset 12)\n'
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'PeerJetty.app'
            executable = app / 'Contents/MacOS/PeerJetty'
            executable.parent.mkdir(parents=True)
            framework = app / 'Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle'
            framework.parent.mkdir(parents=True)
            framework.write_bytes(b'fixture')
            dependency = '@rpath/Sparkle.framework/Versions/B/Sparkle'
            self.assertFalse(module.resolve_dependency(executable, dependency, module.rpaths(commands)))
            paths = module.rpaths(commands + 'cmd LC_RPATH\n cmdsize 48\n path @executable_path/../Frameworks (offset 12)\n')
            self.assertTrue(module.resolve_dependency(executable, dependency, paths))
            framework.unlink()
            self.assertFalse(module.resolve_dependency(executable, dependency, paths))
