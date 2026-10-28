// Interactive bootstrap only. No remote action without an explicit stage confirmation.
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,existsSync,chmodSync,lstatSync} from 'node:fs';
import {randomBytes} from 'node:crypto';
import {createInterface} from 'node:readline/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {checkDeploy} from './check-deploy.mjs';
export const UUID=/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
export function parseDatabaseId(output){
 const ids=[...new Set(output.match(/[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}/gi)??[])];
 if(ids.length!==1)throw new Error('创建输出中无法唯一确定D1 ID。不要重复创建；请先在Dashboard核实结果，重跑时填已有ID。');return ids[0];
}
export function validateSecretFile(raw){
 try {const saved=JSON.parse(raw);if(typeof saved.REPORT_UPLOAD_KEY!=='string'||saved.REPORT_UPLOAD_KEY.length<32)throw new Error();return saved;}
 catch {throw new Error('已有秘密文件无效，不自动覆盖。');}
}
export async function confirmedRun({confirm,run},label,command,args,options={}){
 if(!await confirm(label))throw new Error('操作已取消；此前成功的步骤不会自动回滚。');
 return run(command,args,options);
}
export const plan=[
 '本地：检查Node/npm/Python3；确认后npm ci安装锁定依赖。',
 '本地：输入Worker名称、Cloudflare Account ID、HTTPS origin；备份并写配置。',
 '远程（逐步确认）：wrangler login + whoami，核对目标账号。',
 '远程（可选确认）：创建D1，或绑定你输入的已有D1 ID。',
 '远程（确认）：应用D1 migration。',
 '本地+远程（确认）：生成/复用私有上传密钥，构建，携带secrets-file部署Worker。',
 '手动：Cloudflare Dashboard连接GitHub App，选择仓库、分支、cloudflare根目录和构建命令。'
];
function runner(command,args,options={}){
 const result=spawnSync(command,args,{cwd:fileURLToPath(new URL('..',import.meta.url)),env:{...process.env,WRANGLER_SEND_METRICS:'false'},encoding:'utf8',stdio:options.capture?'pipe':'inherit'});
 if(result.error || result.status!==0)throw new Error(`${command} ${args[0]??''} 未成功完成（退出码 ${result.status??'unknown'}）。停止，不自动重试远程操作；请先核实Dashboard状态。`);
 return result.stdout??'';
}
async function main(){
 const args=process.argv.slice(2);
 if(args.some(a=>!['--dry-run','--help'].includes(a)))throw new Error('用法：bash cloudflare/setup.sh [--dry-run|--help]');
 if(args.length){console.log('Cloudflare 一条命令引导式初始化：\n'+plan.join('\n')+'\n--dry-run只展示计划，不读取凭据、不调用npm/Wrangler、不写文件。');return;}
 if(!process.stdin.isTTY || !process.stdout.isTTY)throw new Error('请在交互终端运行；无人值守环境仅允许 --dry-run。');
 if(Number(process.versions.node.split('.')[0])<22)throw new Error('需要Node.js >=22，推荐24 LTS。');
 const rl=createInterface({input:process.stdin,output:process.stdout});
 const ask=async(q,def='')=>(await rl.question(q+(def?` [${def}]`:'')+': ')).trim()||def;
 const confirm=async(label)=>(await ask(`输入 ${label} 确认（其他内容取消）`))===label;
 const run=runner;
 const ctx={confirm,run};
 const privateDir=new URL('../.setup-private/',import.meta.url);
 const configPath=new URL('../wrangler.jsonc',import.meta.url);
 try{
  console.log('此向导会逐步确认真实云资源修改，可能产生费用；没有自动GitHub授权。取消不回滚已完成操作。');
  run('npm',['--version']);run('python3',['--version']);
  await confirmedRun(ctx,'INSTALL','npm',['ci']);
  const original=readFileSync(configPath,'utf8');const config=JSON.parse(original);
  config.name=await ask('Worker名称（必须与Builds项目同名）',config.name);
  if(!/^[a-z0-9][a-z0-9-]{0,62}$/.test(config.name))throw new Error('Worker名称需小写字母/数字/短横线，最多63字符。');
  config.account_id=await ask('Cloudflare Account ID（Dashboard显示的32位ID；不是API Token）',config.account_id??'');
  if(!/^[a-f0-9]{32}$/i.test(config.account_id))throw new Error('Account ID格式无效。');
  config.vars.PUBLIC_BASE_URL=await ask('报告HTTPS origin（先用自己的workers.dev也可以）',config.vars.PUBLIC_BASE_URL);
  const db=config.d1_databases.find(d=>d.binding==='DB');
  if(!db)throw new Error('缺少DB绑定，请恢复示例配置。');
  const existing=await ask('已有D1 UUID；输入 NEW 创建新数据库',db.database_id==='00000000-0000-0000-0000-000000000000'?'NEW':db.database_id);
  if(existing!=='NEW' && (!UUID.test(existing)||existing==='00000000-0000-0000-0000-000000000000'))throw new Error('D1 UUID格式无效。');
  const probe=structuredClone(config);probe.d1_databases.find(d=>d.binding==='DB').database_id=existing==='NEW'?'12345678-1234-1234-1234-123456789abc':existing;checkDeploy(probe);
  if(!await confirm('CONFIG'))throw new Error('取消；配置未写入。');
  if(existsSync(privateDir)&&lstatSync(privateDir).isSymbolicLink())throw new Error('私有目录不可为符号链接。');
  mkdirSync(privateDir,{recursive:true,mode:0o700});chmodSync(privateDir,0o700);
  const backup=new URL('wrangler.'+Date.now()+'.json',privateDir);writeFileSync(backup,original,{flag:'wx',mode:0o600});
  const save=()=>writeFileSync(configPath,JSON.stringify(config,null,2)+'\n');
  if(existing!=='NEW')db.database_id=existing;
  save();console.log('配置已保存并备份；尚未确认域名绑定。');
  await confirmedRun(ctx,'LOGIN','npx',['--no-install','wrangler','login']);
  run('npx',['--no-install','wrangler','whoami']);
  if(!await confirm('ACCOUNT-'+config.account_id))throw new Error('目标账号未确认；停止。');
  if(existing==='NEW'){
   const output=await confirmedRun(ctx,'CREATE-D1','npx',['--no-install','wrangler','d1','create',db.database_name,'--update-config=false'],{capture:true});
   db.database_id=parseDatabaseId(output);save();console.log('D1已创建并绑定，ID已保存到配置。');
  }
  await confirmedRun(ctx,'MIGRATE','npx',['--no-install','wrangler','d1','migrations','apply',db.database_name,'--remote']);
  console.log('下一步会生成/复用本地上传密钥并设置为线上REPORT_UPLOAD_KEY；若已有线上密钥，这会替换它，需要同步更新CLI。不会打印密钥。');
  if(!await confirm('DEPLOY'))throw new Error('取消发布；配置/数据库可能已准备好，可稍后重跑并复用D1。');
  const secretPath=new URL('secrets.json',privateDir);
  if(existsSync(secretPath)){
   if(lstatSync(secretPath).isSymbolicLink())throw new Error('秘密文件不可为符号链接。');
   validateSecretFile(readFileSync(secretPath,'utf8'));chmodSync(secretPath,0o600);
  }else writeFileSync(secretPath,JSON.stringify({REPORT_UPLOAD_KEY:randomBytes(32).toString('base64url')})+'\n',{mode:0o600,flag:'wx'});
  checkDeploy(config);run('npm',['run','build:ci']);
  run('npx',['--no-install','wrangler','deploy','--secrets-file',fileURLToPath(secretPath)]);
  console.log('部署命令成功。请核验 /healthz、合成上传/删除、源码下载、域名和Cron。上传密钥仅保存在 cloudflare/.setup-private/secrets.json（600），不会打印；请通过安全方式交给CLI。');
  console.log('最后在Cloudflare Dashboard连接GitHub（必须本人授权）：根目录cloudflare；Build npm ci && npm run build:ci；Deploy npm run deploy:ci；构建变量SKIP_DEPENDENCY_INSTALL=1；仅生产分支。详见GITHUB_DEPLOY.md。');
 } finally {rl.close();}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main().catch(e=>{console.error(e.message);process.exitCode=1;});
