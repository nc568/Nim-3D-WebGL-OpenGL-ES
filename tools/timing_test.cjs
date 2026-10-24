// Real browser timer smoke + repeatable static workload profiles. Software GPU
// results are diagnostics only, not hardware performance acceptance thresholds.
const {default: chromium, inflate} = require('@sparticuz/chromium');
const puppeteer = require('puppeteer-core');
const fs = require('fs');
(async()=>{
 if(process.env.USE_BUNDLED_LIBS==='1') {
  const dir=await inflate(require('path').join(__dirname,'../node_modules/@sparticuz/chromium/bin/al2023.tar.br'));
  process.env.LD_LIBRARY_PATH=dir+'/lib:'+(process.env.LD_LIBRARY_PATH||'');
 }
 const browser=await puppeteer.launch({executablePath:await chromium.executablePath(),args:chromium.args,headless:true});
 const reports=[];
 try {
  for(const mode of ['webgl2','webgl1','no-timer']) {
   const legacy=mode==='webgl1';
   const page=await browser.newPage(); const errors=[];
   page.on('pageerror',e=>errors.push(String(e)));
   if(mode==='no-timer') await page.evaluateOnNewDocument(()=>{
    for(const cls of [globalThis.WebGLRenderingContext,globalThis.WebGL2RenderingContext]) {
     if(!cls)continue;
     const original=cls.prototype.getExtension;
     cls.prototype.getExtension=function(name){return name.startsWith('EXT_disjoint_timer_query')?null:original.call(this,name)};
    }
   });
   await page.goto('http://127.0.0.1:8080/' +(legacy?'?webgl1':''));
   await page.waitForFunction(()=>typeof globalThis.softgfxTiming==='function');
   // Reject blocking operations and reads without observed availability.
   await page.evaluate(()=>{
    const gl=document.querySelector('canvas').getContext(new URLSearchParams(location.search).has('webgl1')?'webgl':'webgl2');
    const ext=gl.getExtension(new URLSearchParams(location.search).has('webgl1')?'EXT_disjoint_timer_query':'EXT_disjoint_timer_query_webgl2');
    globalThis.timingGl=gl;
    gl.finish=()=>{throw Error('Profiler must not call finish')};
    gl.readPixels=()=>{throw Error('Profiler must not read pixels')};
    if(ext) {
     const owner=new URLSearchParams(location.search).has('webgl1')?ext:gl;
     const name=owner===gl?'getQueryParameter':'getQueryObjectEXT';
     const original=owner[name].bind(owner); const available=new Set();
     const beginName=owner===gl?'beginQuery':'beginQueryEXT';
     const begin=owner[beginName].bind(owner);
     owner[beginName]=(target,q)=>{available.delete(q);return begin(target,q)};
     owner[name]=(q,key)=>{
      if(key===0x8867){const value=original(q,key);if(value)available.add(q);else available.delete(q);return value;}
      if(key===0x8866&&!available.has(q)) throw Error('Read of unavailable timer query');
      return original(q,key);
     };
    }
   });
   const cases=(legacy||mode==='no-timer')?[{name:mode==='no-timer'?'timer-unavailable':'T0',post:false,fxaa:false,scale:1}]:[
    {name:'direct',post:false,fxaa:false,scale:1},
    {name:'neutral',post:true,fxaa:false,scale:1},
    {name:'FXAA',post:true,fxaa:true,scale:1},
    {name:'FXAA-scale85',post:true,fxaa:true,scale:.85}];
   for(const config of cases) {
    await page.evaluate(c=>{
     for(const [id,v] of [['post-enabled',c.post],['post-fxaa',c.fxaa],['post-dither',false],['post-scale',c.scale]]) {
      const e=document.getElementById(id);if(e.type==='checkbox')e.checked=v;else e.value=v;
      e.dispatchEvent(new Event('input'));
     }
    },config);
    await page.click('#measure-timing');
    await page.waitForFunction(()=>softgfxTiming().frames>=180,{timeout:60000});
    await page.click('#measure-timing');
    const report=await page.evaluate(()=>softgfxTiming());
    if(report.cpuSamples<100 || report.cpuP95Ms<report.cpuMedianMs) throw Error('Missing CPU measurements: '+JSON.stringify(report));
    if(report.gpuSamples && (!report.gpuSupported || report.gpuP95Ms<report.gpuMedianMs)) throw Error('Invalid GPU report');
    if(!report.gpuSamples && report.gpuMedianMs!==null) throw Error('Missing GPU reported as zero time');
    if(mode==='no-timer' && (report.gpuSupported || report.gpuSamples || report.gpuMedianMs!==null)) throw Error('Unavailable timer reported GPU data');
    reports.push({workload:config.name,...report});
   }
   // In-flight context loss; measurements must restart, not reuse old samples.
   await page.click('#measure-timing');
   await page.waitForFunction(()=>softgfxTiming().frames>40);
   await page.evaluate(()=>{globalThis.loss=timingGl.getExtension('WEBGL_lose_context');loss.loseContext()});
   await page.waitForFunction(()=>document.getElementById('status').textContent==='lost');
   const lostReport=await page.evaluate(()=>softgfxTiming());
   if(lostReport.cpuSamples || lostReport.gpuSamples) throw Error('Lost context retained measurements');
   await page.evaluate(()=>loss.restoreContext());
   await page.waitForFunction(()=>document.getElementById('status').textContent.startsWith('webgl'));
   await page.waitForFunction(()=>softgfxTiming().frames>=60);
   await page.click('#measure-timing');
   if(await page.evaluate(()=>timingGl.getError())) throw Error('GL error in timing test');
   if(errors.length) throw Error(errors.join('\n'));
   await page.close();
  }
 } finally {await browser.close()}
 fs.writeFileSync('build/timing-report.json',JSON.stringify({environment:'Chromium headless software/ANGLE; NOT physical GPU benchmark',reports},null,2));
 console.log(JSON.stringify(reports,null,2));
})().catch(e=>{console.error(e);process.exit(1)});
