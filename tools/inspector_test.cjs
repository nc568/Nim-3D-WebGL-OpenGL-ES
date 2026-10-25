const assert=require('assert/strict'),fs=require('fs');
module.exports=async function inspectorTest(browser,engine) {
 const report={schemaVersion:1,engine,passed:false,cases:[]};
 const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(String(e)));
 try {
  await page.goto('http://127.0.0.1:8080/');
  await page.waitForFunction(()=>typeof softgfxRender==='function');
  assert(await page.evaluate(()=>!globalThis.softgfxDebug&&!globalThis.softgfxInspector&&!document.getElementById('softgfx-inspector')));
  for(const legacy of [false,true]) {
   await page.goto('http://127.0.0.1:8080/?debug'+(legacy?'&webgl1':''));
   await page.waitForFunction(()=>typeof softgfxRender==='function'&&typeof softgfxInspector==='object');
   await page.click('#softgfx-inspector > summary');
   await page.evaluate(()=>{
    const gl=document.querySelector('canvas').getContext(new URLSearchParams(location.search).has('webgl1')?'webgl':'webgl2');
    globalThis.inspectorReads=0;
    for(const name of ['readPixels','finish','getError'])gl[name]=()=>{inspectorReads++;throw Error('Unexpected inspector GL operation');};
    globalThis.inspectorIntervals=new Set();const si=setInterval,ci=clearInterval;
    globalThis.setInterval=(...args)=>{const id=si(...args);inspectorIntervals.add(id);return id;};
    globalThis.clearInterval=id=>{inspectorIntervals.delete(id);ci(id);};
    globalThis.inspectorXss=false;
    softgfxDebug.mark('<img src=x onerror="globalThis.inspectorXss=true">');
    softgfxInspector.refresh();
   });
   assert.equal(await page.evaluate(()=>document.querySelectorAll('#softgfx-inspector img').length),0);
   assert(await page.evaluate(()=>document.getElementById('softgfx-inspector-events').textContent.includes('<img')));
   // Invalid configuration must leave old budgets unchanged and show an error.
   await page.evaluate(()=>{document.getElementById('softgfx-budget-bytes').value='-1';});
   await page.click('#softgfx-budget-apply');
   assert(await page.evaluate(()=>softgfxDebug.snapshot().budgets===null&&document.getElementById('softgfx-inspector-status').textContent.length>0));
   await page.evaluate(()=>{document.getElementById('softgfx-budget-draws').value='0';document.getElementById('softgfx-budget-bytes').value='0';});
   await page.click('#softgfx-budget-apply');
   await page.evaluate(()=>{softgfxRender();softgfxRender();softgfxInspector.refresh();});
   assert(await page.evaluate(()=>softgfxDebug.snapshot().budgetStatus.breachFrames>=2));
   await page.evaluate(()=>{const f=document.getElementById('softgfx-inspector-filter');f.value='problems';f.dispatchEvent(new Event('change'));});
   assert(await page.evaluate(()=>document.getElementById('softgfx-inspector-events').textContent.includes('budget-exceeded')));
   // Select after capture must show frozen values, not a live alias.
   await page.evaluate(()=>{document.getElementById('softgfx-capture-label').value='checkpoint';});
   await page.click('#softgfx-capture');
   const id=await page.evaluate(()=>Number(document.getElementById('softgfx-capture-list').value));
   const frozen=await page.evaluate(id=>softgfxDebug.getCapture(id),id);
   await page.evaluate(()=>{softgfxAdvance(0.1);softgfxInspector.refresh();});
   assert.deepEqual(await page.evaluate(id=>softgfxDebug.getCapture(id),id),frozen);
   // Exercise actual export code without downloading a file into browser-specific paths.
   await page.evaluate(()=>{
    globalThis.inspectorExport=null;
    URL.createObjectURL=blob=>{globalThis.inspectorExport=blob;return 'blob:softgfx-test';};
    URL.revokeObjectURL=()=>{};HTMLAnchorElement.prototype.click=function(){};
   });
   await page.click('#softgfx-capture-export');
   assert.deepEqual(await page.evaluate(async()=>JSON.parse(await inspectorExport.text())),frozen);
   for(let i=0;i<4;i++)await page.click('#softgfx-capture');
   assert(await page.evaluate(id=>softgfxDebug.getCapture(id)===null&&document.querySelectorAll('#softgfx-capture-list option').length===4,id));
   await page.screenshot({path:`build/inspector-${engine}-${legacy?'webgl1':'webgl2'}.png`});
   await page.click('#softgfx-inspector-auto');
   assert.equal(await page.evaluate(()=>inspectorIntervals.size),1);
   await page.click('#softgfx-inspector-stop');
   assert(await page.evaluate(()=>inspectorIntervals.size===0&&softgfxDebug.snapshot().stopped&&document.getElementById('softgfx-capture').disabled));
   const snapshot=await page.evaluate(()=>softgfxDebug.snapshot());
   await page.evaluate(()=>{softgfxInspector.dispose();softgfxDebug.mark('ignored');});
   assert(await page.evaluate(()=>!globalThis.softgfxInspector&&!document.getElementById('softgfx-inspector')&&inspectorIntervals.size===0&&inspectorReads===0&&!inspectorXss));
   assert.equal(await page.evaluate(()=>softgfxDebug.snapshot().total),snapshot.total);
   report.cases.push({api:legacy?'webgl1':'webgl2',capture:frozen,passed:true});
  }
  assert.deepEqual(errors,[]);report.passed=true;
  console.log('Inspector filters / budget UI / captures / export / teardown PASS:',engine);
 } catch(e){report.error=String(e);report.pageErrors=errors;
  try {await page.screenshot({path:`build/inspector-${engine}-failure.png`});}catch{}
  throw e;
 }
 finally {fs.writeFileSync(`build/inspector-${engine}.json`,JSON.stringify(report,null,2));await page.close();}
};
