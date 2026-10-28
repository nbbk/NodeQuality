import io
import json
import os
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app import ReportApp

class ReportsTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.now = 1700000000
        self.key = 'test-only-'+'a'*40
        self.app = ReportApp(db=self.directory.name+'/db',base_url='https://reports.example.test',upload_key=self.key,clock=lambda:self.now)
        self.payload = {'schema_version':1,'title':'合成测试节点','sections':[{'title':'硬件 / Hardware','content':'CPU: Synthetic 4 cores\nRAM: 8 GiB'}]}
    def tearDown(self):
        self.directory.cleanup()
    def request(self,method,path,payload=None,token=None,ctype='application/json',length=None):
        body=json.dumps(payload,ensure_ascii=False).encode() if payload is not None else b''
        env={'REQUEST_METHOD':method,'PATH_INFO':path,'CONTENT_TYPE':ctype,'CONTENT_LENGTH':str(len(body) if length is None else length),'wsgi.input':io.BytesIO(body)}
        if token is not None: env['HTTP_AUTHORIZATION']='Bearer '+token
        state={}
        def start(status,headers): state.update(status=int(status[:3]),headers=dict(headers))
        data=b''.join(self.app(env,start))
        return state,data
    def upload(self,payload=None):
        state,data=self.request('POST','/api/v1/reports',payload or self.payload,self.key)
        self.assertEqual(state['status'],201,data)
        return json.loads(data)
    def test_roundtrip_and_security_headers(self):
        report=self.upload()
        state,data=self.request('GET','/r/'+report['id'])
        self.assertEqual(state['status'],200)
        self.assertIn('合成测试节点',data.decode())
        self.assertEqual(state['headers']['Cache-Control'],'no-store')
        self.assertIn("frame-ancestors 'none'",state['headers']['Content-Security-Policy'])
        self.assertNotIn(report['delete_token'].encode(),data)
        self.assertEqual(report['url'],'https://reports.example.test/r/'+report['id'])
    def test_xss_ansi_bidi(self):
        self.payload['title']='<script>alert(1)</script>'
        self.payload['sections'][0]['content']='</pre><img src=x onerror=alert(1)>\x1b[31mRED\x1b[0m\u202e'
        report=self.upload()
        _,data=self.request('GET','/r/'+report['id'])
        self.assertNotIn(b'<script>',data)
        self.assertNotIn(b'<img',data)
        self.assertIn(b'&lt;img',data)
        self.assertNotIn(b'\x1b',data)
        self.assertNotIn('\u202e',data.decode())
    def test_deletion_token_hashed_and_authorized(self):
        report=self.upload()
        with self.app.connect() as conn:
            self.assertNotIn(report['delete_token'],str(conn.execute('SELECT * FROM reports').fetchall()))
        path='/api/v1/reports/'+report['id']
        self.assertEqual(self.request('DELETE',path,token=self.key)[0]['status'],401)
        self.assertEqual(self.request('DELETE',path,token=report['delete_token'])[0]['status'],204)
        self.assertEqual(self.request('GET','/r/'+report['id'])[0]['status'],404)
        self.assertEqual(self.request('DELETE',path,token=report['delete_token'])[0]['status'],404)
    def test_expiry_and_cleanup(self):
        report=self.upload(); self.now+=7*86400
        self.assertEqual(self.request('GET','/r/'+report['id'])[0]['status'],404)
        with self.app.connect() as conn: self.assertEqual(conn.execute('SELECT COUNT(*) FROM reports').fetchone()[0],0)
    def test_validation_and_auth(self):
        self.assertEqual(self.request('POST','/api/v1/reports',self.payload)[0]['status'],401)
        self.assertEqual(self.request('POST','/api/v1/reports',self.payload,'中文')[0]['status'],401)
        cases=[{},[],dict(self.payload,schema_version=True),dict(self.payload,title=''),dict(self.payload,title=' '*161+'x'),dict(self.payload,title='\x1b[31m'),dict(self.payload,unexpected=True),dict(self.payload,sections=[]),dict(self.payload,sections=[{'title':'x','content':{}}]),dict(self.payload,sections=[{'title':'x','content':'x'*262145}])]
        for payload in cases:
            self.assertEqual(self.request('POST','/api/v1/reports',payload,self.key)[0]['status'],400)
        self.assertEqual(self.request('POST','/api/v1/reports',self.payload,self.key,length=1048577)[0]['status'],413)
        self.assertEqual(self.request('POST','/api/v1/reports',self.payload,self.key,ctype='text/plain')[0]['status'],415)
    def test_rate_limit_shared_between_workers(self):
        self.app.rate_limit=1
        self.upload()
        self.assertEqual(self.request('POST','/api/v1/reports',self.payload,self.key)[0]['status'],429)
        other=ReportApp(db=self.app.db,base_url=self.app.base_url,upload_key=self.key,clock=lambda:self.now)
        other.rate_limit=1; self.app=other
        self.assertEqual(self.request('POST','/api/v1/reports',self.payload,self.key)[0]['status'],429)
        self.now+=3601; self.upload()
    def test_capacity(self):
        self.app.max_reports=1; self.upload()
        self.assertEqual(self.request('POST','/api/v1/reports',self.payload,self.key)[0]['status'],503)
    def test_no_listing_and_path_traversal(self):
        for path in ['/r/','/api/v1/reports','/r/../../etc/passwd','/r/'+'a'*32]:
            self.assertEqual(self.request('GET',path)[0]['status'],404)
    def test_source_and_robots(self):
        state,data=self.request('GET','/source.tar.gz')
        self.assertEqual(state['status'],200); self.assertTrue(data.startswith(b'\x1f\x8b'))
        self.assertIn(b'Disallow: /',self.request('GET','/robots.txt')[1])
    def test_configuration(self):
        with self.assertRaises(ValueError): ReportApp(db=self.app.db,base_url='http://evil.test',upload_key=self.key)
        with self.assertRaises(ValueError): ReportApp(db=self.app.db,base_url='https://example.test/path',upload_key=self.key)
        with self.assertRaises(ValueError): ReportApp(db=self.app.db,base_url=self.app.base_url,upload_key='short')

if __name__=='__main__': unittest.main()
