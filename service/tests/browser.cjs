// Synthetic-only browser smoke test; requires local Playwright and Chromium.
const {chromium}=require('playwright');
const {spawn}=require('child_process');
const fs=require('fs'), os=require('os'), path=require('path');
(async()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'nq-browser-'));
 const key='synthetic-only-browser-test-key-123456789';
 const child=spawn('python3',['app.py'],{cwd:path.resolve(__dirname,'..'),env:{...process.env,PUBLIC_BASE_URL:'http://127.0.0.1:8080',ALLOW_HTTP_LOCALHOST:'1',REPORT_DB:path.join(dir,'db.sqlite3'),REPORT_UPLOAD_KEY:key},stdio:'ignore'});
 let browser;
 try{
  for(let n=0;n<50;n++){try{if((await fetch('http://127.0.0.1:8080/healthz')).ok)break;}catch{} await new Promise(r=>setTimeout(r,100));}
  const payload={schema_version:1,title:'合成节点 · 东京 / Synthetic',sections:[{title:'硬件性能',content:'CPU: Synthetic 4 cores\nMemory: 8 GiB\nDisk: 100 GiB\n'+'long-output-'.repeat(90)},{title:'网络质量',content:'Synthetic fixture only\n</pre><img src=x onerror="window.xss=true">\n无真实主机或 IP 信息'}]};
  const res=await fetch('http://127.0.0.1:8080/api/v1/reports',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+key},body:JSON.stringify(payload)});
  if(res.status!==201)throw Error('Upload failed '+res.status);
  const report=await res.json();
  browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
  for(const [label,width,height] of [['phone',390,844],['desktop',1440,1000]]){
   const page=await browser.newPage({viewport:{width,height}});
   await page.goto(report.url);
   if(await page.locator('h1').textContent()!==payload.title)throw Error('Missing title');
   if(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth))throw Error('Horizontal overflow');
   if(await page.locator('img,script').count())throw Error('Unsafe rendered content');
   await page.getByRole('link',{name:'网络质量',exact:true}).click();
   if(!page.url().endsWith('#s1'))throw Error('Navigation failure');
   await page.reload(); await page.goBack(); await page.goForward();
   await page.screenshot({path:path.join(dir,label+'.png'),fullPage:true});
   await page.close();
  }
  console.log('PASS phone + desktop layout, XSS, section navigation, refresh/back/forward; screenshots: '+dir);
 }finally{if(browser)await browser.close();child.kill();}
})().catch(e=>{console.error(e);process.exitCode=1;});
