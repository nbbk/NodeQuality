import contextlib
import importlib.util
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('nq_setup',Path(__file__).resolve().parents[1]/'setup.py')
setup=importlib.util.module_from_spec(spec);spec.loader.exec_module(setup)

class SetupTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
    def tearDown(self):self.temp.cleanup()
    def run_setup(self,*args):
        stream=io.StringIO()
        with contextlib.redirect_stdout(stream),contextlib.redirect_stderr(stream):
            result=setup.main(list(args),self.root)
        return result,stream.getvalue()
    def test_private_and_idempotent(self):
        result,out=self.run_setup('--url','https://reports.example.test','--configure-only')
        self.assertEqual(result,0,out)
        env=(self.root/'.env').read_bytes();client=(self.root/'client.env').read_bytes()
        key=dict(line.split('=',1) for line in env.decode().splitlines())['REPORT_UPLOAD_KEY']
        self.assertNotIn(key,out)
        for filename in ('.env','client.env'):self.assertEqual((self.root/filename).stat().st_mode&0o777,0o600)
        self.assertEqual(self.run_setup('--configure-only')[0],0)
        self.assertEqual((self.root/'.env').read_bytes(),env);self.assertEqual((self.root/'client.env').read_bytes(),client)
    def test_invalid_url_and_port(self):
        for url in ['http://example.test','https://u:p@example.test','https://example.test/path','https://example.test/$X','https://example.test\nX=1']:
            self.assertEqual(self.run_setup('--url',url,'--configure-only')[0],1)
        self.assertFalse((self.root/'.env').exists())
        self.assertEqual(self.run_setup('--url','https://example.test','--port','22','--configure-only')[0],1)
    def test_no_overwrite(self):
        self.run_setup('--url','https://reports.example.test','--configure-only')
        old=(self.root/'.env').read_bytes()
        self.assertEqual(self.run_setup('--url','https://different.test','--configure-only')[0],1)
        self.assertEqual(old,(self.root/'.env').read_bytes())
    def test_symlink_refused(self):
        target=self.root/'secret';target.write_text('original')
        (self.root/'.env').symlink_to(target)
        self.assertEqual(self.run_setup('--url','https://reports.example.test','--configure-only')[0],1)
        self.assertEqual(target.read_text(),'original')
    def test_mock_docker_explicit_yes_and_no_secret_args(self):
        with patch.dict(os.environ,{'COMPOSE_FILE':'wrong.yaml','COMPOSE_PROFILES':'unsafe','COMPOSE_PROJECT_NAME':'other'}),patch.object(setup.shutil,'which',return_value='/mock/docker'),patch.object(setup.subprocess,'run') as run:
            code,out=self.run_setup('--url','https://reports.example.test','--yes')
            self.assertEqual(code,0,out);self.assertEqual(run.call_count,2)
            args=run.call_args.args[0]
            self.assertIn('up',args);self.assertIn('--build',args)
            self.assertEqual(args[args.index('-f')+1],str(self.root/'compose.yaml'))
            for name in ('COMPOSE_FILE','COMPOSE_PROFILES','COMPOSE_PROJECT_NAME'):
                self.assertNotIn(name,run.call_args.kwargs['env'])
            key=dict(line.split('=',1) for line in (self.root/'.env').read_text().splitlines())['REPORT_UPLOAD_KEY']
            self.assertNotIn(key,str(args));self.assertNotIn(key,out)
    def test_no_start_without_confirmation(self):
        with patch.object(setup.shutil,'which',return_value='/mock/docker'),patch.object(setup.subprocess,'run') as run,patch.object(setup.sys.stdin,'isatty',return_value=False):
            self.assertEqual(self.run_setup('--url','https://reports.example.test')[0],0)
            self.assertEqual(run.call_count,1)
    def test_no_docker_clear_failure(self):
        with patch.object(setup.shutil,'which',return_value=None):
            code,out=self.run_setup('--url','https://reports.example.test','--yes')
            self.assertEqual(code,1);self.assertIn('Docker',out)
        self.assertFalse((self.root/'.env').exists())

if __name__=='__main__':unittest.main()
