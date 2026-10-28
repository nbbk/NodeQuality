import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {confirmedRun,parseDatabaseId,validateSecretFile} from '../scripts/setup.mjs';
test('setup rejects denied stage without calling mocked command runner',async()=>{
 let calls=0;await assert.rejects(()=>confirmedRun({confirm:async()=>false,run:()=>calls++},'DEPLOY','wrangler',['deploy']),/取消/);assert.equal(calls,0);
});
test('setup executes only explicit stage using mock; failure is not retried',async()=>{
 const calls=[];const ctx={confirm:async label=>label==='CREATE-D1',run:(...args)=>{calls.push(args);throw new Error('uncertain');}};
 await assert.rejects(()=>confirmedRun(ctx,'CREATE-D1','wrangler',['d1','create','synthetic']),/uncertain/);assert.equal(calls.length,1);
});
test('D1 result parsing requires one unambiguous UUID',()=>{
 assert.equal(parseDatabaseId('database_id = "12345678-1234-1234-1234-123456789abc"'),'12345678-1234-1234-1234-123456789abc');assert.throws(()=>parseDatabaseId('unknown'),/不要重复创建/);assert.throws(()=>parseDatabaseId('12345678-1234-1234-1234-123456789abc 12345678-1234-1234-1234-123456789abd'));
});
test('dry-run requires no npm/Wrangler/Python PATH and leaves config unchanged',()=>{
 const config=new URL('../wrangler.jsonc',import.meta.url);const before=readFileSync(config,'utf8');
 const result=spawnSync(process.execPath,[new URL('../scripts/setup.mjs',import.meta.url).pathname,'--dry-run'],{env:{PATH:''},encoding:'utf8'});assert.equal(result.status,0,result.stderr);assert.match(result.stdout,/只展示计划/);assert.equal(readFileSync(config,'utf8'),before);
});

test('malformed private secret error never discloses file contents',()=>{
 assert.throws(()=>validateSecretFile('{"REPORT_UPLOAD_KEY":"synthetic-secret-do-not-echo'),e=>e.message==='已有秘密文件无效，不自动覆盖。');
});
