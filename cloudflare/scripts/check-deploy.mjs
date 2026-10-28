// Refuse accidental deployment of the example D1 binding/origin. No network calls.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
export function checkDeploy(config) {
  const db=config.d1_databases?.find(d=>d.binding==='DB');
  if (!db || !/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(db.database_id) || db.database_id==='00000000-0000-0000-0000-000000000000') throw new Error('Set DB.database_id to your existing D1 database UUID first; this command never provisions a database.');
  const origin=new URL(config.vars?.PUBLIC_BASE_URL);
  if(origin.protocol!=='https:' || origin.pathname!=='/' || origin.search || origin.hash || origin.username || origin.password || /(^|\.)example\.(com|org|net)$|\.example$/.test(origin.hostname)) throw new Error('Set PUBLIC_BASE_URL to your real HTTPS report origin, not the example.');
  if(!config.name)throw new Error('Set name to the exact Worker name selected in Cloudflare Builds.');
}
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href){
  try {checkDeploy(JSON.parse(readFileSync(new URL('../wrangler.jsonc',import.meta.url),'utf8')));console.log('Deployment config checked. Confirm remote D1 migration and runtime secret before enabling uploads.');}
  catch(error){console.error('Deployment blocked:',error.message,'Keep wrangler.jsonc valid JSON (without comments).');process.exitCode=1;}
}
