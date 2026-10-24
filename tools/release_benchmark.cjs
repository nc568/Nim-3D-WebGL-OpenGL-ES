const assert=require('assert/strict'),fs=require('fs');
// Compatible with Puppeteer and Playwright; no GPU timing or speed thresholds.
module.exports = async function benchmark(browser, engine) {
 const report={schemaVersion:1,engine,version:browser.version(),platform:process.platform,
   arch:process.arch,scope:'CPU-only release observations, not FPS; no cross-machine ranking',passed:false,rows:[]};
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
  assert.deepEqual(errors,[]);report.passed=true;
  console.log('Release CPU benchmark PASS:',engine,report.rows.length,'cases');
 } catch(e) {report.error=String(e);throw e;}
 finally {fs.writeFileSync(`build/release-${engine}.json`,JSON.stringify(report,null,2));await page.close();}
};
