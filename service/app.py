"""NodeQuality self-hosted reports. AGPL-3.0-or-later; see ../LICENSE."""
from contextlib import contextmanager
import hashlib
import hmac
import html
import io
import json
import os
import re
import secrets
import sqlite3
import threading
import time
from datetime import datetime, timezone
from urllib.parse import urlsplit

CSS = '''*{box-sizing:border-box}body{margin:0;background:#f3f6fa;color:#17243a;font:16px/1.65 system-ui,-apple-system,sans-serif}main{max-width:1080px;margin:auto;padding:48px 24px}header{margin-bottom:32px}.brand{color:#146957;font-size:13px;font-weight:750;letter-spacing:.12em}h1{font-size:clamp(25px,5vw,42px);line-height:1.2;overflow-wrap:anywhere}h2{font-size:19px;margin:0 0 16px}.sub,footer{color:#526279;font-size:14px}.pill{display:inline-block;border:1px solid #bdcfc9;border-radius:99px;padding:4px 12px;color:#146957;font-size:12px}nav{display:flex;gap:8px;flex-wrap:wrap;margin:24px 0}a{color:#146957}nav a{background:white;border-radius:8px;padding:8px 12px;text-decoration:none}section{background:#fff;border:1px solid #dce4ed;border-radius:14px;padding:24px;margin:16px 0;min-width:0}pre{font:13px/1.65 ui-monospace,SFMono-Regular,Consolas,monospace;white-space:pre-wrap;overflow-wrap:anywhere;word-break:break-word;margin:0;color:#33445d}footer{margin-top:32px}button{font:inherit;background:#146957;color:#fff;border:0;border-radius:7px;padding:8px 16px}@media(max-width:480px){main{padding:28px 14px}section{padding:18px 14px}pre{font-size:12px}}@media print{body{background:white}main{padding:0}nav{display:none}section{break-inside:avoid}}'''
CONTROL = re.compile(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]')
ANSI = re.compile(r'\x1b(?:\][^\x07\x1b]*(?:\x07|\x1b\\)|\[[0-?]*[ -/]*[@-~])')
ID = re.compile(r'^[A-Za-z0-9_-]{32}$')

def clean(value):
    return CONTROL.sub('', ANSI.sub('', value))

def stamp(value):
    return datetime.fromtimestamp(value, timezone.utc).isoformat().replace('+00:00', 'Z')

def page(title, body):
    return ('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow,noarchive"><title>' + html.escape(title) + '</title><link rel="stylesheet" href="/style.css"></head><body><main>' + body + '</main></body></html>').encode()

class ReportApp:
    def __init__(self, db=None, base_url=None, upload_key=None, clock=time.time):
        self.base_url = (base_url or os.environ.get('PUBLIC_BASE_URL', '')).rstrip('/')
        parts = urlsplit(self.base_url)
        dev = os.environ.get('ALLOW_HTTP_LOCALHOST') == '1' and parts.hostname in ('localhost', '127.0.0.1')
        if (parts.scheme != 'https' and not (dev and parts.scheme == 'http')) or not parts.netloc or parts.path or parts.query or parts.fragment or parts.username:
            raise ValueError('PUBLIC_BASE_URL must be an HTTPS origin (localhost HTTP requires ALLOW_HTTP_LOCALHOST=1)')
        self.upload_key = upload_key or os.environ.get('REPORT_UPLOAD_KEY', '')
        if len(self.upload_key) < 32:
            raise ValueError('REPORT_UPLOAD_KEY must contain at least 32 characters')
        self.db = db or os.environ.get('REPORT_DB', '/data/reports.sqlite3')
        self.clock = clock
        self.max_bytes = int(os.environ.get('MAX_UPLOAD_BYTES', '1048576'))
        self.retention = int(os.environ.get('RETENTION_DAYS', '7'))
        self.max_reports = int(os.environ.get('MAX_REPORTS', '10000'))
        self.rate_limit = int(os.environ.get('UPLOADS_PER_HOUR', '30'))
        if not 1 <= self.retention <= 365 or not 1024 <= self.max_bytes <= 10485760 or self.max_reports < 1 or self.rate_limit < 1:
            raise ValueError('Invalid service limits')
        with self.connect() as conn:
            conn.executescript('CREATE TABLE IF NOT EXISTS reports(id TEXT PRIMARY KEY, payload TEXT NOT NULL, delete_hash TEXT NOT NULL, created INTEGER NOT NULL, expires INTEGER NOT NULL); CREATE INDEX IF NOT EXISTS report_expiry ON reports(expires); CREATE TABLE IF NOT EXISTS uploads(created INTEGER NOT NULL);')

    @contextmanager
    def connect(self):
        conn = sqlite3.connect(self.db, timeout=10)
        try:
            conn.execute('PRAGMA secure_delete=ON')
            with conn:
                yield conn
        finally:
            conn.close()

    def purge(self):
        with self.connect() as conn:
            conn.execute('DELETE FROM reports WHERE expires<=?', (int(self.clock()),))
            conn.execute('DELETE FROM uploads WHERE created<=?', (int(self.clock())-3600,))

    def __call__(self, env, start):
        try:
            status, kind, body, extra = self.route(env)
        except (ValueError, UnicodeError, json.JSONDecodeError):
            status, kind, body, extra = 400, 'application/json', b'{"error":"Invalid report request"}', []
        except sqlite3.Error:
            status, kind, body, extra = 503, 'application/json', b'{"error":"Storage temporarily unavailable"}', []
        names = {200:'OK',201:'Created',204:'No Content',400:'Bad Request',401:'Unauthorized',404:'Not Found',405:'Method Not Allowed',413:'Content Too Large',415:'Unsupported Media Type',429:'Too Many Requests',503:'Service Unavailable'}
        headers = [('Content-Type',kind+'; charset=utf-8'),('Content-Length',str(len(body))),('Cache-Control','no-store'),('X-Content-Type-Options','nosniff'),('X-Robots-Tag','noindex, nofollow, noarchive'),('Referrer-Policy','no-referrer'),('Content-Security-Policy',"default-src 'none'; style-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"),('Permissions-Policy','camera=(), microphone=(), geolocation=()')]+extra
        start(str(status)+' '+names[status],headers)
        return [body]

    def reply(self, status, data, extra=None):
        return status, 'application/json', json.dumps(data, ensure_ascii=False).encode(), extra or []

    def route(self, env):
        path, method = env.get('PATH_INFO',''), env.get('REQUEST_METHOD','GET')
        if method == 'GET' and path == '/healthz':
            return self.reply(200, {'status':'ok'})
        if method == 'GET' and path == '/style.css':
            return 200, 'text/css', CSS.encode(), []
        if method == 'GET' and path == '/robots.txt':
            return 200, 'text/plain', b'User-agent: *\nDisallow: /\n', []
        if method == 'GET' and path == '/':
            return 200, 'text/html', page('NodeQuality · 私有部署', '<header><span class="brand">NODEQUALITY / REPORTS</span><h1>让每一次测试，<br>都有清晰的答案。</h1><p class="sub">自托管节点测试报告 · 无公开目录 · 无第三方追踪</p></header><section><h2>通过专属链接查看报告</h2><p>请从你的工具箱生成、审阅并主动上传报告。拥有分享链接的任何人都能阅读，请勿上传秘密。</p></section><footer>基于 NodeQuality 开源项目 · AGPL-3.0 · <a href="/source.tar.gz">下载本站服务源码</a></footer>'), []
        if method == 'GET' and path == '/source.tar.gz':
            import tarfile
            from pathlib import Path
            root = Path(__file__).resolve().parent
            stream = io.BytesIO()
            with tarfile.open(fileobj=stream,mode='w:gz') as archive:
                for name in ('app.py','requirements.txt','Dockerfile','compose.yaml','README.md','LICENSE','api-contract.json','tests/test_app.py','tests/browser.cjs','tests/smoke.py','setup.py','setup.sh','tests/test_setup.py','.dockerignore','.gitignore'):
                    candidate = root / name
                    if candidate.is_file():
                        archive.add(candidate,arcname='service/'+name)
            return 200, 'application/gzip', stream.getvalue(), [('Content-Disposition','attachment; filename="nodequality-service-source.tar.gz"')]
        self.purge()
        if path == '/api/v1/reports' and method == 'POST':
            auth = env.get('HTTP_AUTHORIZATION','')
            if not hmac.compare_digest(auth.encode(), ('Bearer '+self.upload_key).encode()):
                return self.reply(401, {'error':'Upload authorization required'})
            if env.get('CONTENT_TYPE','').split(';')[0].strip() != 'application/json':
                return self.reply(415, {'error':'Expected application/json'})
            length = int(env.get('CONTENT_LENGTH') or '0')
            if length > self.max_bytes:
                return self.reply(413, {'error':'Report is too large'})
            if length <= 0:
                raise ValueError('Missing length')
            raw = env['wsgi.input'].read(length)
            if len(raw) != length:
                raise ValueError('Truncated request')
            payload = self.validate(json.loads(raw))
            now = int(self.clock())
            expires = now + self.retention*86400
            token, report_id = secrets.token_urlsafe(32), secrets.token_urlsafe(24)
            with self.connect() as conn:
                conn.execute('BEGIN IMMEDIATE')
                if conn.execute('SELECT COUNT(*) FROM uploads').fetchone()[0] >= self.rate_limit:
                    return self.reply(429, {'error':'Upload limit reached'}, [('Retry-After','3600')])
                if conn.execute('SELECT COUNT(*) FROM reports').fetchone()[0] >= self.max_reports:
                    return self.reply(503, {'error':'Report capacity reached'})
                conn.execute('INSERT INTO reports VALUES(?,?,?,?,?)',(report_id,json.dumps(payload),hashlib.sha256(token.encode()).hexdigest(),now,expires))
                conn.execute('INSERT INTO uploads VALUES(?)',(now,))
            return self.reply(201, {'id':report_id,'url':self.base_url+'/r/'+report_id,'delete_token':token,'expires_at':stamp(expires)})
        prefix = '/api/v1/reports/' if path.startswith('/api/v1/reports/') else '/r/'
        report_id = path.removeprefix(prefix)
        if not path.startswith(prefix) or not ID.fullmatch(report_id):
            return self.reply(404, {'error':'Report not found'})
        with self.connect() as conn:
            row = conn.execute('SELECT payload,delete_hash,created,expires FROM reports WHERE id=? AND expires>?',(report_id,int(self.clock()))).fetchone()
            if not row:
                return self.reply(404, {'error':'Report not found or expired'})
            if method == 'DELETE' and prefix == '/api/v1/reports/':
                authorization = env.get('HTTP_AUTHORIZATION','')
                if not authorization.startswith('Bearer '):
                    return self.reply(401, {'error':'Invalid deletion token'})
                token = authorization[len('Bearer '):]
                if not hmac.compare_digest(hashlib.sha256(token.encode()).hexdigest(),row[1]):
                    return self.reply(401, {'error':'Invalid deletion token'})
                conn.execute('DELETE FROM reports WHERE id=?',(report_id,))
                return 204, 'application/json', b'', []
        if method != 'GET' or prefix != '/r/':
            return self.reply(405, {'error':'Method not allowed'})
        payload = json.loads(row[0])
        esc = html.escape
        nav = ''.join('<a href="#s'+str(i)+'">'+esc(s['title'])+'</a>' for i,s in enumerate(payload['sections']))
        sections = ''.join('<section id="s'+str(i)+'"><h2>'+esc(s['title'])+'</h2><pre>'+esc(s['content'])+'</pre></section>' for i,s in enumerate(payload['sections']))
        body = '<header><span class="brand">NODEQUALITY / REPORTS</span><h1>'+esc(payload['title'])+'</h1><span class="pill">节点测试报告</span><p class="sub">上传于 '+stamp(row[2])+' · 到期 '+stamp(row[3])+'</p></header><nav aria-label="报告章节">'+nav+'</nav>'+sections+'<footer>报告由上传者提供，未经独立验证。链接不等于访问控制；请勿转发敏感内容。<br>自托管 · 无第三方资源 · <a href="/source.tar.gz">AGPL 服务源码</a></footer>'
        return 200, 'text/html', page(payload['title'], body), []

    def validate(self, payload):
        if not isinstance(payload,dict) or set(payload)-{'schema_version','title','sections','generated_at','tool_version','upstream_commit'} or type(payload.get('schema_version')) is not int or payload['schema_version'] != 1:
            raise ValueError('Unsupported schema')
        if not isinstance(payload.get('title'),str) or not payload['title'].strip() or len(payload['title']) > 160:
            raise ValueError('Invalid title')
        sections = payload.get('sections')
        if not isinstance(sections,list) or not 1 <= len(sections) <= 32:
            raise ValueError('Invalid sections')
        for section in sections:
            if not isinstance(section,dict) or set(section) != {'title','content'} or not isinstance(section['title'],str) or not section['title'].strip() or len(section['title']) > 100 or not isinstance(section['content'],str) or len(section['content']) > 262144:
                raise ValueError('Invalid section')
            section['title'],section['content'] = clean(section['title']),clean(section['content'])
            if not section['title'].strip():
                raise ValueError('Empty clean title')
        for key in ('generated_at','tool_version','upstream_commit'):
            if key in payload and (not isinstance(payload[key],str) or len(payload[key])>100):
                raise ValueError('Invalid metadata')
        payload['title'] = clean(payload['title'])
        if not payload['title'].strip():
            raise ValueError('Empty clean title')
        return payload

def create_app():
    os.umask(0o077)
    app = ReportApp()
    def sweep():
        while True:
            try:
                app.purge()
            except sqlite3.Error:
                pass  # Requests also enforce expiry even if cleanup is delayed.
            time.sleep(60)
    threading.Thread(target=sweep, daemon=True).start()
    return app

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--purge',action='store_true')
    args = parser.parse_args()
    app = create_app()
    if args.purge:
        app.purge()
    else:
        from wsgiref.simple_server import make_server
        class QuietHandler(__import__('wsgiref.simple_server',fromlist=['WSGIRequestHandler']).WSGIRequestHandler):
            def log_message(self,*args):
                pass
        make_server('127.0.0.1',8080,app,handler_class=QuietHandler).serve_forever()
