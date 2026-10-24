// Playwright engines are NOT the shipped Safari/Firefox binaries.
const fs = require('fs'), assert = require('assert/strict');
const engine = process.env.BROWSER_ENGINE;
if (!['firefox','webkit'].includes(engine)) throw Error('BROWSER_ENGINE must be firefox or webkit');
const report = {schemaVersion:1, engine, platform:process.platform, arch:process.arch,
  passed:false, cases:[], errors:[]};
(async () => {
 let browser;
 try {
  if (engine==='webkit') assert.equal(process.arch,'arm64','Expected macOS ARM runner');
  browser = await require('playwright')[engine].launch({headless:true,
    ...(engine==='firefox' ? {firefoxUserPrefs:{'webgl.force-enabled':true}} : {})});
  report.version=browser.version();
  for (const legacy of [false,true]) {
   const page = await browser.newPage();
   const errors=[], rows=[];
   page.on('pageerror',e=>{errors.push(String(e)); report.errors.push(String(e)); console.error(String(e));});
   page.on('console',msg=>{
    console.log(msg.text());
    if(msg.text().startsWith('GPU_WORKLOAD ')) rows.push(JSON.parse(msg.text().slice(13)));
   });
   const name=legacy?'webgl1':'webgl2';
   try {
    await page.goto('http://127.0.0.1:8080/gpu-test.html'+(legacy?'?webgl1':''));
    await page.waitForFunction(()=>document.querySelector('#status')?.textContent==='PASS',null,{timeout:120000});
    assert.deepEqual(errors,[]); assert.equal(rows.length,2);
    assert(rows.every(r=>r.api===name), 'Silent context downgrade');
    report.cases.push({name,passed:true,workloads:rows});
   } finally { await page.close(); }
  }
  for (const query of ['debug','debug&webgl1','debug&fallback','debug&webgl1&fallback']) {
   const page=await browser.newPage(); const errors=[];
   page.on('pageerror',e=>{errors.push(String(e)); report.errors.push(String(e)); console.error(String(e));});
   try {
    await page.goto('http://127.0.0.1:8080/?'+query);
    await page.waitForFunction(()=>typeof softgfxRender==='function');
    const result=await page.evaluate(()=>{
     const canvas=document.querySelector('canvas');
     const gl=canvas.getContext(new URLSearchParams(location.search).has('webgl1')?'webgl':'webgl2');
     if(!gl) throw Error('Expected WebGL context unavailable');
     softgfxDebug.setBudgets({drawCalls:0,uploadBytes:0});
     let seed=568;
     for(let i=0;i<60;i++) {
      seed=(Math.imul(seed,1664525)+1013904223)>>>0;
      canvas.width=64+seed%640; canvas.height=64+(seed>>>12)%480;
      softgfxRender();
      if(gl.getError()) throw Error('GL error during resize fuzz');
     }
     if(softgfxDebug.snapshot().budgetStatus.breachFrames!==60 || softgfxDebug.snapshot().budgetStatus.episodes!==1) throw Error('Budget episode tracking failed');
     softgfxDebug.setBudgets(null);
     for(let i=0;i<300;i++) softgfxDebug.mark('bounded-'+i);
     const snapshot=softgfxDebug.snapshot();
     if(!snapshot.graphics || !snapshot.graphics.maxTextureSize) throw Error("Missing debug capabilities");
     if(snapshot.events.length!==256 || snapshot.overwritten<44) throw Error('Unbounded recorder');
     const first=snapshot.events[0].message; snapshot.events[0].message='mutated';
     if(softgfxDebug.snapshot().events[0].message!==first) throw Error('Mutable recorder export');
     if(performance.getEntriesByType('resource').some(r=>r.name.endsWith('.wasm'))) throw Error('WASM loaded');
     return softgfxDebug.snapshot();
    });
    fs.writeFileSync(`build/debug-${engine}-${query.replaceAll('&','-')}.json`,JSON.stringify(result,null,2));
    await page.screenshot({path:`build/${engine}-${query.replaceAll('&','-')}.png`});
    assert.deepEqual(errors,[]);
    report.cases.push({name:query,passed:true});
   } finally { await page.close(); }
  }
  await require('./release_benchmark.cjs')(browser,engine);
  report.passed=true;
 } catch(e) {report.errors.push(e.stack||String(e)); throw e;}
 finally {
  fs.writeFileSync(`build/cross-${engine}.json`,JSON.stringify(report,null,2));
  if(browser) await browser.close();
 }
})().catch(e=>{console.error(e); const detail=(report.errors.join('\n')||String(e)).slice(-7000).replaceAll('%','%25').replaceAll('\r','%0D').replaceAll('\n','%0A'); console.log('::error title=Cross-browser failure::'+detail); process.exitCode=1;});
