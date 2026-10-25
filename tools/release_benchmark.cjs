const assert=require('assert/strict'),fs=require('fs');
// Compatible with Puppeteer and Playwright; no GPU timing or speed thresholds.
module.exports = async function benchmark(browser, engine) {
 const report={schemaVersion:1,engine,version:browser.version(),platform:process.platform,
   arch:process.arch,scope:'CPU algorithms + host submission including DOM updates; not GPU elapsed or FPS; no cross-machine ranking',passed:false,rows:[]};
 // Puppeteer version() is asynchronous; Playwright's is synchronous.
 report.version=await report.version;
 const page=await browser.newPage(); const errors=[];
 page.on('pageerror',e=>errors.push(String(e)));
 try {
  await page.goto('http://127.0.0.1:8080/benchmark.html');
  await page.waitForFunction(()=>typeof softgfxBench==='function');
  report.environment=await page.evaluate(()=>({userAgent:navigator.userAgent,
    hardwareConcurrency:navigator.hardwareConcurrency,isolated:crossOriginIsolated}));
  for(const count of [64,1024,8192]) for(const moving of [false,true]) for(const dense of [false,true]) {
   const r=await page.evaluate(({count,moving,dense})=>JSON.parse(softgfxBench(count,moving,dense)),{count,moving,dense});
   assert.equal(r.buildMode,'release');assert.equal(r.warmup,20);assert.equal(r.samples,41);
   assert.equal(r.instances,count);assert.equal(r.moving,moving);assert.equal(r.dense,dense);
   assert(dense ? r.visible===count : r.visible>0 && r.visible<count);
   assert.equal(r.changedRecords,moving?count*41:0);assert.equal(r.skipped,moving?0:41);
   for(const key of ['packing','forcedPacking','rebuild','flatQuery','gridQuery']) {
    const s=r[key];assert.equal(s.rawMs.length,41);
    assert(s.rawMs.every(v=>Number.isFinite(v)&&v>=0));
    const sorted=[...s.rawMs].sort((a,b)=>a-b);
    assert.equal(s.medianMs,sorted[20]);assert.equal(s.p95Ms,sorted[38]);assert.equal(s.minMs,sorted[0]);
   }
   if(!moving)assert(r.rebuild.rawMs.every(v=>v===0));
   report.rows.push(r);
  }
  report.submission=[];
  for(const legacy of [false,true]) for(const fallback of [false,true]) for(const moving of [false,true]) {
   await page.goto('http://127.0.0.1:8080/?'+[legacy?'webgl1':'',fallback?'fallback':''].filter(Boolean).join('&'));
   await page.waitForFunction(()=>typeof softgfxAdvance==='function');
   const sample=await page.evaluate(async moving=>{
    const canvas=document.querySelector('canvas');canvas.width=320;canvas.height=240;
    softgfxRender();
    const times=[];
    for(let i=0;i<20;i++) {
     await new Promise(requestAnimationFrame);
     if(moving)softgfxAdvance(1/60);else softgfxRender();
    }
    const before=softgfxTiming();
    for(let i=0;i<41;i++) {
     await new Promise(requestAnimationFrame); // scheduling wait is OUTSIDE timing
     const start=performance.now();
     if(moving)softgfxAdvance(1/60);else softgfxRender();
     times.push(performance.now()-start);
    }
    const after=softgfxTiming(),sorted=[...times].sort((a,b)=>a-b);
    return {moving,warmup:20,samples:41,width:canvas.width,height:canvas.height,
     api:after.api,mode:after.instanceMode,post:after.postEnabled,drawCalls:after.drawCalls,
     targetBytes:after.targetBytes,uploadBytes:after.instanceUploadBytes-before.instanceUploadBytes,
     updates:after.instanceUpdates-before.instanceUpdates,
     postUniformCalls:after.postUniformCalls-before.postUniformCalls,postUniformSkips:after.postUniformSkips-before.postUniformSkips,
     cameraUploads:after.cameraUploads-before.cameraUploads,cameraSkips:after.cameraSkips-before.cameraSkips,
     medianMs:sorted[20],p95Ms:sorted[38],rawMs:times};
   },moving);
   assert.equal(sample.api,legacy?'webgl1':'webgl2');
   if(fallback)assert.equal(sample.mode,'fallbackDraws');
   assert(sample.rawMs.every(v=>Number.isFinite(v)&&v>=0));
   assert(sample.drawCalls>0);
   assert.equal(sample.postUniformCalls,0);assert.equal(sample.postUniformSkips,legacy?0:205);
   assert.equal(sample.cameraUploads,0);assert.equal(sample.cameraSkips,82);
   if(!moving)assert.equal(sample.updates,0);
   else assert(sample.updates>0);
   if(sample.mode==='fallbackDraws'||!moving)assert.equal(sample.uploadBytes,0);
   else assert(sample.uploadBytes>0);
   report.submission.push({...sample,forcedFallback:fallback});
  }
  await require('./gpu_evidence.cjs').collect(browser,engine);
  await require('./soak_test.cjs')(browser,engine);
  assert.deepEqual(errors,[]);report.passed=true;
  console.log('Release CPU benchmark PASS:',engine,report.rows.length,'cases');
 } catch(e) {report.error=String(e);throw e;}
 finally {fs.writeFileSync(`build/release-${engine}.json`,JSON.stringify(report,null,2));await page.close();}
};
