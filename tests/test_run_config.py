import importlib.util
from pathlib import Path
import tempfile
import unittest
spec=importlib.util.spec_from_file_location('run_config',Path(__file__).resolve().parents[1]/'scripts/run.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class ConfigTest(unittest.TestCase):
    def test_safe_parse_not_execution(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'client.env';p.write_text("export NQ_UPLOAD_KEY='$(touch should-not-exist)'\nNQ_UPLOAD_URL=https://reports.example/api/v1/reports\n");p.chmod(0o600)
            data=module.load_config(p)
            self.assertEqual(data['NQ_UPLOAD_KEY'],'$(touch should-not-exist)')
            self.assertFalse((Path(d)/'should-not-exist').exists())
            p.chmod(0o644)
            with self.assertRaises(ValueError):module.load_config(p)
    def test_bad_configuration(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'client.env'
            for value in ['PATH=/tmp','NQ_UPLOAD_KEY=a\nNQ_UPLOAD_KEY=b','echo unsafe','NQ_UPLOAD_KEY=a; echo bad']:
                p.write_text(value);p.chmod(0o600)
                with self.assertRaises(ValueError):module.load_config(p)
