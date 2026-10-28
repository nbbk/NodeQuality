"""Local synthetic HTTP smoke, never connects to any external service."""
import http.client
import json
from pathlib import Path
import sys
import tempfile
import threading
from wsgiref.simple_server import make_server, WSGIRequestHandler
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app import ReportApp
class Quiet(WSGIRequestHandler):
    def log_message(self,*args): pass
with tempfile.TemporaryDirectory() as directory:
    key='synthetic-smoke-key-'+'0'*32
    app=ReportApp(db=directory+'/db',base_url='https://synthetic.example.test',upload_key=key)
    server=make_server('127.0.0.1',0,app,handler_class=Quiet)
    thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
    try:
        def request(method,path,body=None,token=None):
            conn=http.client.HTTPConnection('127.0.0.1',server.server_port,timeout=5)
            headers={'Content-Type':'application/json'}
            if token: headers['Authorization']='Bearer '+token
            conn.request(method,path,body,headers)
            response=conn.getresponse(); status=response.status; data=response.read(); conn.close()
            return status,data
        fixture=Path(__file__).resolve().parents[1]/'api-contract.json'
        status,body=request('POST','/api/v1/reports',fixture.read_bytes(),key)
        assert status==201,(status,body)
        report=json.loads(body)
        status,body=request('GET','/r/'+report['id']); assert status==200 and '合成报告'.encode() in body
        status,_=request('DELETE','/api/v1/reports/'+report['id'],token=report['delete_token']); assert status==204
        status,_=request('GET','/r/'+report['id']); assert status==404
        print('PASS localhost HTTP create/read/delete/missing, synthetic fixture only')
    finally:
        server.shutdown();server.server_close();thread.join(timeout=5)
