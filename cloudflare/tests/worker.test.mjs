import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { Miniflare } from 'miniflare';
import worker, { validate } from '../src/worker.js';
let mf,db;
const key='synthetic-only-upload-key-32-chars-or-more';
const fixture=JSON.parse(await readFile(new URL('./fixture.json',import.meta.url),'utf8'));
const post=(payload=fixture,headers={})=>mf.dispatchFetch('https://reports.example.com/api/v1/reports',{method:'POST',headers:{authorization:'Bearer '+key,'content-type':'application/json',...headers},body:JSON.stringify(payload)});
before(async()=>{
  mf=new Miniflare({name:'reports',modules:true,scriptPath:new URL('../src/worker.js',import.meta.url).pathname,modulesRules:[{type:'ESModule',include:['**/*.js']}],compatibilityDate:'2026-08-01',d1Databases:['DB'],assets:{directory:new URL('../public',import.meta.url).pathname,binding:'ASSETS',workerName:'reports',routerConfig:{invoke_user_worker_ahead_of_assets:true,has_user_worker:true}},bindings:{PUBLIC_BASE_URL:'https://reports.example.com',REPORT_UPLOAD_KEY:key,UPLOADS_PER_HOUR:'30',MAX_REPORTS:'10000'}});
  db=await mf.getD1Database('DB');
  const sql=await readFile(new URL('../migrations/0001_reports.sql',import.meta.url),'utf8');
  // D1 exec accepts one SQL statement per line, including the complete trigger.
  await db.exec(sql.replace(/CREATE TRIGGER[\s\S]*?END;/,s=>s.replaceAll('\n',' ')));
});
after(async()=>{await mf?.dispose();});
test('schema boundaries use Unicode characters, strip ANSI and bidi, reject unknown/blank',()=>{
  assert.equal(validate({schema_version:1,title:'🧪'.repeat(160),sections:[{title:'a',content:'\x1b[31m<x>\u202e'}]}).sections[0].content,'<x>');
  for(const p of [{...fixture,title:'x'.repeat(161)},{...fixture,title:'\u202e'},{...fixture,extra:1},{...fixture,schema_version:true},{...fixture,sections:[{title:'a',content:'b',html:true}]}])assert.throws(()=>validate(p));
});
test('real workerd+D1: upload authorization, create, escaped read, delete',async()=>{
  assert.equal((await post(fixture,{authorization:''})).status,401);
  assert.equal((await post(fixture,{'content-type':'text/plain'})).status,415);
  assert.equal((await post({...fixture,schema_version:2})).status,400);
  assert.equal((await post({...fixture,title:'x'.repeat(1048577)})).status,413);
  const r=await post({...fixture,title:'<script>alert(1)</script>',sections:[{title:'<img>',content:'\x1b[31m<script>evil()</script>\u202e'}]});assert.equal(r.status,201);
  const p=await r.json();assert.match(p.id,/^[\w-]{32}$/);assert.match(p.delete_token,/^[\w-]{43}$/);assert.equal(p.url,'https://reports.example.com/r/'+p.id);
  const stored=await db.prepare('SELECT * FROM reports WHERE id=?').bind(p.id).first();assert.notEqual(stored.delete_hash,p.delete_token);assert.equal(stored.delete_hash.length,64);
  const page=await mf.dispatchFetch(p.url);assert.equal(page.status,200);const html=await page.text();assert.ok(html.includes('&lt;script&gt;'));assert.ok(!html.includes('<script>'));assert.ok(!html.includes('\u202e'));assert.match(page.headers.get('content-security-policy'),/default-src 'none'/);
  assert.equal((await mf.dispatchFetch('https://reports.example.com/api/v1/reports/'+p.id)).status,405);
  assert.equal((await mf.dispatchFetch('https://reports.example.com/api/v1/reports/'+p.id,{method:'DELETE',headers:{authorization:'Bearer wrong'}})).status,401);
  assert.equal((await mf.dispatchFetch('https://reports.example.com/api/v1/reports/'+p.id,{method:'DELETE',headers:{authorization:'Bearer '+p.delete_token}})).status,204);
  assert.equal((await mf.dispatchFetch(p.url)).status,404);
});
test('expiry enforced before cleanup; scheduled purge clears data and old quota',async()=>{
  const p=await (await post()).json();await db.prepare('UPDATE reports SET expires=1 WHERE id=?').bind(p.id).run();
  assert.equal((await mf.dispatchFetch(p.url)).status,404);
  await db.prepare('INSERT INTO uploads VALUES(1)').run();const pending=[];
  await worker.scheduled({}, {DB:db},{waitUntil:p=>pending.push(p)});await Promise.all(pending);
  assert.equal(await db.prepare('SELECT * FROM reports WHERE id=?').bind(p.id).first(),null);
  assert.equal((await db.prepare('SELECT COUNT(*) AS n FROM uploads WHERE created=1').first()).n,0);
});
test('atomic quota under parallel writes and no public index',async()=>{
  await db.exec('DELETE FROM uploads;');
  const responses=await Promise.all(Array.from({length:35},()=>post()));
  assert.equal(responses.filter(r=>r.status===201).length,30);
  assert.equal(responses.filter(r=>r.status===429).length,5);
  const home=await mf.dispatchFetch('https://reports.example.com/');assert.equal(home.status,200);assert.ok((await home.text()).includes('无公开目录'));
  assert.equal((await mf.dispatchFetch('https://reports.example.com/api/v1/reports')).status,404);
});

test('deployed source offer asset is readable and cache protected',async()=>{
 const r=await mf.dispatchFetch('https://reports.example.com/source.tar.gz');assert.equal(r.status,200);assert.equal(r.headers.get('cache-control'),'no-store');assert.match(r.headers.get('content-type'),/application\/gzip/);const bytes=new Uint8Array(await r.arrayBuffer());assert.equal(bytes[0],0x1f);assert.equal(bytes[1],0x8b);
});
