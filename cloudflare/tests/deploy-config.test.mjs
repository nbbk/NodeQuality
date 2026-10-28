import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {checkDeploy} from '../scripts/check-deploy.mjs';
test('production preflight refuses shipped placeholders without remote changes',()=>{
 const c=JSON.parse(readFileSync(new URL('../wrangler.jsonc',import.meta.url),'utf8'));
 // Always synthetic: test does not depend on whether deployer has personalized config.
 c.d1_databases[0].database_id='00000000-0000-0000-0000-000000000000';assert.throws(()=>checkDeploy(c),/database UUID/);
 c.d1_databases[0].database_id='12345678-1234-1234-1234-123456789abc';c.vars.PUBLIC_BASE_URL='https://reports.example.com';assert.throws(()=>checkDeploy(c),/real HTTPS/);
 c.vars.PUBLIC_BASE_URL='https://synthetic-test.invalid';assert.doesNotThrow(()=>checkDeploy(c));
});
