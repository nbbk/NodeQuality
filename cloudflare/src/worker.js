// NodeQuality self-hosted reports — AGPL-3.0-or-later, see LICENSE and ../NOTICE.md.
import CSS from './style.js';
const ID = /^[A-Za-z0-9_-]{32}$/;
const headers = {'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','X-Robots-Tag':'noindex, nofollow, noarchive','Referrer-Policy':'no-referrer','Content-Security-Policy':"default-src 'none'; style-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",'Permissions-Policy':'camera=(), microphone=(), geolocation=()'};
const response = (status, body, type='application/json', extra={}) => new Response(status === 204 ? null : type === 'application/json' ? JSON.stringify(body) : body, {status,headers:{...headers,'Content-Type':type+'; charset=utf-8',...extra}});
const fail = (status,error,extra={}) => response(status,{error},'application/json',extra);
const esc = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#x27;'}[c]));
const stamp = n => new Date(n*1000).toISOString().replace('.000Z','Z');
const page = (title,body) => '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow,noarchive"><title>'+esc(title)+'</title><link rel="stylesheet" href="/style.css"></head><body><main>'+body+'</main></body></html>';
export function clean(value) {return value.replace(/\x1b(?:\][^\x07\x1b]*(?:\x07|\x1b\\)|\[[0-?]*[ -/]*[@-~])/g,'').replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]/g,'');}
const len = s => [...s].length;
const object = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const titleValid = (s,max) => typeof s === 'string' && s.trim() && clean(s).trim() && len(s)<=max;
export function validate(p) {
  if (!object(p) || Object.keys(p).some(k=>!['schema_version','title','sections','generated_at','tool_version','upstream_commit'].includes(k)) || p.schema_version!==1 || !titleValid(p.title,160) || !Array.isArray(p.sections) || p.sections.length<1 || p.sections.length>32) throw new Error('validation');
  for (const s of p.sections) {
    if (!object(s) || Object.keys(s).sort().join(',')!=='content,title' || !titleValid(s.title,100) || typeof s.content!=='string' || len(s.content)>262144) throw new Error('validation');
    s.title=clean(s.title); s.content=clean(s.content);
  }
  for (const k of ['generated_at','tool_version','upstream_commit']) if (k in p && (typeof p[k]!=='string' || len(p[k])>100)) throw new Error('validation');
  p.title=clean(p.title);return p;
}
async function hash(s) {return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s)))].map(n=>n.toString(16).padStart(2,'0')).join('');}
async function equal(a,b) { const x=await hash(a),y=await hash(b);let diff=0;for(let i=0;i<x.length;i++) diff|=x.charCodeAt(i)^y.charCodeAt(i);return diff===0; }
function random(n) {return btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(n)))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');}
function config(env) {
  const origin=new URL(env.PUBLIC_BASE_URL);
  if (origin.protocol!=='https:' || origin.username || origin.password || origin.pathname!=='/' || origin.search || origin.hash || typeof env.REPORT_UPLOAD_KEY!=='string' || env.REPORT_UPLOAD_KEY.length<32) throw new Error('configuration');
  const c={origin:origin.origin,days:Number(env.RETENTION_DAYS??7),max:Number(env.MAX_UPLOAD_BYTES??1048576),cap:Number(env.MAX_REPORTS??10000),rate:Number(env.UPLOADS_PER_HOUR??30)};
  if (!Object.values(c).slice(1).every(Number.isSafeInteger) || c.days<1 || c.days>365 || c.max<1024 || c.max>1048576 || c.cap<1 || c.rate<1) throw new Error('configuration');return c;
}
async function purge(env,now) {await env.DB.batch([env.DB.prepare('DELETE FROM reports WHERE expires<=?').bind(now),env.DB.prepare('DELETE FROM uploads WHERE created<=?').bind(now-3600)]);}
async function readBody(request,max) {
  if (Number(request.headers.get('content-length'))>max) return null;
  const reader=request.body?.getReader();if(!reader) throw new Error('validation');let size=0;const chunks=[];
  while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>max){await reader.cancel();return null;}chunks.push(value);}
  const all=new Uint8Array(size);let at=0;for(const c of chunks){all.set(c,at);at+=c.length;}return new TextDecoder('utf-8',{fatal:true}).decode(all);
}
async function route(request,env) {
  const path=new URL(request.url).pathname,method=request.method;
  if(method==='GET' && path==='/style.css')return response(200,CSS,'text/css');
  if(method==='GET' && path==='/robots.txt')return response(200,'User-agent: *\nDisallow: /\n','text/plain');
  if(method==='GET' && path==='/source.tar.gz') {
    const asset=await env.ASSETS.fetch(new Request(new URL('/source.tar.gz',request.url)));
    return new Response(asset.body,{status:asset.status,headers:{...headers,'Content-Type':'application/gzip','Content-Disposition':'attachment; filename="nodequality-cloudflare-source.tar.gz"'}});
  }
  let c;try{c=config(env);}catch{return fail(503,'Service configuration required');}
  if(method==='GET' && path==='/healthz') {await env.DB.prepare('SELECT id FROM reports LIMIT 1').all();return response(200,{status:'ok'});}
  if(method==='GET' && path==='/')return response(200,page('NodeQuality · 私有部署','<header><span class="brand">NODEQUALITY / REPORTS</span><h1>让每一次测试，<br>都有清晰的答案。</h1><p class="sub">自托管节点测试报告 · 无公开目录 · 无第三方追踪</p></header><section><h2>通过专属链接查看报告</h2><p>请从你的工具箱生成、审阅并主动上传报告。拥有分享链接的任何人都能阅读，请勿上传秘密。</p></section><footer>基于 NodeQuality 开源项目 · AGPL-3.0 · <a href="/source.tar.gz">下载本站服务源码</a></footer>'),'text/html');
  const now=Math.floor(Date.now()/1000);
  if(path==='/api/v1/reports' && method==='POST') {
    if(!await equal(request.headers.get('authorization')??'','Bearer '+env.REPORT_UPLOAD_KEY))return fail(401,'Upload authorization required');
    if((request.headers.get('content-type')??'').split(';')[0].trim()!=='application/json')return fail(415,'Expected application/json');
    let p;try{const body=await readBody(request,c.max);if(body===null)return fail(413,'Report is too large');p=validate(JSON.parse(body));}catch{return fail(400,'Invalid report request');}
    await purge(env,now);
    const id=random(24),token=random(32),expires=now+c.days*86400;
    // Single SQLite write statement serializes quota check + insertion; trigger records only successful uploads.
    const result=await env.DB.prepare('INSERT INTO reports(id,payload,delete_hash,created,expires) SELECT ?,?,?,?,? WHERE (SELECT COUNT(*) FROM uploads WHERE created>?)<? AND (SELECT COUNT(*) FROM reports WHERE expires>?)<?').bind(id,JSON.stringify(p),await hash(token),now,expires,now-3600,c.rate,now,c.cap).run();
    if(result.meta.changes===0){const n=await env.DB.prepare('SELECT COUNT(*) AS n FROM uploads WHERE created>?').bind(now-3600).first();return n.n>=c.rate?fail(429,'Upload limit reached',{'Retry-After':'3600'}):fail(503,'Report capacity reached');}
    return response(201,{id,url:c.origin+'/r/'+id,delete_token:token,expires_at:stamp(expires)});
  }
  const prefix=path.startsWith('/api/v1/reports/')?'/api/v1/reports/':'/r/';
  const id=path.slice(prefix.length);
  if(!path.startsWith(prefix) || !ID.test(id))return fail(404,'Report not found');
  const row=await env.DB.prepare('SELECT payload,delete_hash,created,expires FROM reports WHERE id=? AND expires>?').bind(id,now).first();
  if(!row)return fail(404,'Report not found or expired');
  if(method==='DELETE' && prefix==='/api/v1/reports/') {
    const auth=request.headers.get('authorization')??'';
    if(!auth.startsWith('Bearer ') || !await equal(await hash(auth.slice(7)),row.delete_hash))return fail(401,'Invalid deletion token');
    await env.DB.prepare('DELETE FROM reports WHERE id=?').bind(id).run();return response(204,null);
  }
  if(method!=='GET' || prefix!=='/r/')return fail(405,'Method not allowed');
  const p=JSON.parse(row.payload);
  const nav=p.sections.map((s,i)=>'<a href="#s'+i+'">'+esc(s.title)+'</a>').join('');
  const sections=p.sections.map((s,i)=>'<section id="s'+i+'"><h2>'+esc(s.title)+'</h2><pre>'+esc(s.content)+'</pre></section>').join('');
  return response(200,page(p.title,'<header><span class="brand">NODEQUALITY / REPORTS</span><h1>'+esc(p.title)+'</h1><span class="pill">节点测试报告</span><p class="sub">上传于 '+stamp(row.created)+' · 到期 '+stamp(row.expires)+'</p></header><nav aria-label="报告章节">'+nav+'</nav>'+sections+'<footer>报告由上传者提供，未经独立验证。链接不等于访问控制；请勿转发敏感内容。<br>自托管 · 无第三方资源 · <a href="/source.tar.gz">AGPL 服务源码</a></footer>'),'text/html');
}
export default {
  async fetch(request,env) {try{return await route(request,env);}catch{return fail(503,'Storage temporarily unavailable');}},
  async scheduled(event,env,ctx) {ctx.waitUntil(purge(env,Math.floor(Date.now()/1000)));}
};
