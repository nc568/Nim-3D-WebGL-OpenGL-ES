const {default: chromium, inflate} = require('@sparticuz/chromium');
const puppeteer = require('puppeteer-core');
(async () => {
 if(process.env.USE_BUNDLED_LIBS==='1') {
  const dir=await inflate(require('path').join(__dirname,'../node_modules/@sparticuz/chromium/bin/al2023.tar.br'));
  process.env.LD_LIBRARY_PATH=dir+'/lib:'+(process.env.LD_LIBRARY_PATH||'');
 }
 const browser = await puppeteer.launch({executablePath: await chromium.executablePath(), args: chromium.args, headless:true});
 try {
 for(const suffix of ['gpu-test.html','gpu-test.html?webgl1']) {
  const page=await browser.newPage(); const errors=[];
  page.on('pageerror',e=>{errors.push(String(e)); console.error(e.stack || String(e));});
  page.on('console',m=>{if(m.type()==='log') console.log(m.text())});
  await page.goto('http://127.0.0.1:8080/'+suffix);
  await page.waitForFunction(()=>document.querySelector('#status').textContent==='PASS');
  if(errors.length) throw Error(errors.join('\n'));
  console.log('GPU territory/instances/post/environment/culling/motion oracles PASS:',suffix);
  await page.close();
 }
 if(process.env.GPU_ONLY==='1') return;
 await require('./release_benchmark.cjs')(browser,'chromium');
 for (const suffix of (process.env.TEST_UI==='1' ? ['', '?webgl1', '?fallback', '?webgl1&fallback', 'ui.html'] : ['', '?webgl1', '?fallback', '?webgl1&fallback'])) {
  const page = await browser.newPage(); const errors=[];
  page.on('pageerror', e=>errors.push(String(e)));
  await page.goto('http://127.0.0.1:8080/'+suffix);
  await page.waitForFunction(()=>document.querySelector('#status').textContent.startsWith('webgl'));
  if(suffix==='ui.html') await page.waitForFunction(()=>document.querySelector('#uir-viewport').textContent.includes('UIRelays'));
  const result = await page.evaluate(()=>{
   const c=document.querySelector('canvas');
   const gl=c.getContext(new URLSearchParams(location.search).has('webgl1')?'webgl':'webgl2');
   let seed=568;
   for(let i=0;i<200;i++) {
    seed=(Math.imul(seed,1664525)+1013904223)>>>0;
    c.width=32+seed%900; c.height=32+(seed>>>12)%700;
    globalThis.softgfxRender();
    if(gl.getError()) throw Error('GL error during seeded resize fuzz');
   }
   c.width=800; c.height=600; globalThis.softgfxRender();
   const pixel=new Uint8Array(4); gl.readPixels(400,300,1,1,gl.RGBA,gl.UNSIGNED_BYTE,pixel);
   const image = new Uint8Array(c.width*c.height*4);
   gl.readPixels(0,0,c.width,c.height,gl.RGBA,gl.UNSIGNED_BYTE,image);
   let red=0, dark=0;
   for(let i=0;i<image.length;i+=4) {
    if(image[i]>image[i+2]*1.3 && image[i]>100) red++;
    if(image[i]<130 && image[i+1]<150) dark++;
   }
   if(red<100 || dark<1000 || pixel[3]!==255) throw Error('Missing arena/car geometry: '+[red,dark,pixel]);
   return {api:document.querySelector('#status').textContent,error:gl.getError(),pixel:[...pixel],wasm:performance.getEntriesByType('resource').some(x=>x.name.endsWith('.wasm'))};
  });
  if(errors.length || result.error || result.wasm) throw Error(JSON.stringify({errors,result}));
  // Keep a synchronous readback fingerprint; the default framebuffer is transient.
  const fingerprint = async () => page.evaluate(()=>{
   globalThis.softgfxRender();
   const c=document.querySelector('canvas');
   const gl=c.getContext(new URLSearchParams(location.search).has('webgl1')?'webgl':'webgl2');
   const bytes=new Uint8Array(c.width*c.height*4);
   gl.readPixels(0,0,c.width,c.height,gl.RGBA,gl.UNSIGNED_BYTE,bytes);
   let hash=2166136261;
   for(const value of bytes) hash=Math.imul(hash^value,16777619)>>>0;
   if(gl.getError()) throw Error('Readback GL error');
   return hash;
  });
  // Post target cache, failure rollback, settings fuzz and context restoration.
  await page.evaluate(()=>{
   const c=document.querySelector('canvas');
   const legacy=new URLSearchParams(location.search).has('webgl1');
   const gl=c.getContext(legacy?'webgl':'webgl2');
   const create=gl.createFramebuffer.bind(gl), remove=gl.deleteFramebuffer.bind(gl);
   let allocations=0, deletions=0;
   gl.createFramebuffer=function(){allocations++;return create()};
   gl.deleteFramebuffer=function(f){deletions++;return remove(f)};
   const input=(id,value)=>{
    const e=document.getElementById(id);
    if(e.type==='checkbox') e.checked=value; else e.value=value;
    e.dispatchEvent(new Event('input'));
   };
   for(let i=0;i<20;i++) globalThis.softgfxRender();
   if(allocations || deletions) throw Error('Stable post target reallocates');
   if(!legacy) {
    const check=gl.checkFramebufferStatus.bind(gl);
    gl.checkFramebufferStatus=function(){return 0x8CD6};
    c.width=801;
    let rejected=false;
    try {globalThis.softgfxRender()} catch(e) {rejected=true}
    gl.checkFramebufferStatus=check;
    if(!rejected || allocations!==1 || deletions!==1) throw Error('Failed FBO resize leaked');
    c.width=800;globalThis.softgfxRender();
    if(allocations!==1 || deletions!==1) throw Error('Failed resize discarded good target');
   }
   for(let i=0;i<60;i++) {
    input('post-enabled',i%5!==0);
    input('post-fxaa',i%2===0);
    input('post-dither',i%3===0);
    input('post-scale',0.7+(i%7)*0.05);
    c.width=101+(i*29)%300;c.height=91+(i*37)%240;
    globalThis.softgfxRender();
    if(gl.getError()) throw Error('Post settings/resize GL error');
   }
   if(legacy && (allocations || deletions)) throw Error('T0 allocated a post target');
   input('post-enabled',true);input('post-fxaa',true);input('post-dither',true);
   // Non-default scale stays enabled during the later context-loss tests.
   input('post-scale',0.85);
   c.width=800;c.height=600;globalThis.softgfxRender();
   if(!legacy && !document.getElementById('post-stats').textContent.startsWith('680×510'))
    throw Error('Render scale not applied');
   gl.createFramebuffer=create;gl.deleteFramebuffer=remove;
  });
  for(const id of ['env-sky','env-fog','env-shadows']) {
   const before=await fingerprint();
   await page.$eval('#'+id,e=>{e.checked=false;e.dispatchEvent(new Event('input'))});
   const after=await fingerprint();
   if(before===after) throw Error('Environment toggle had no pixel effect: '+id);
   await page.$eval('#'+id,e=>{e.checked=true;e.dispatchEvent(new Event('input'))});
   if(await fingerprint()!==before) throw Error('Environment toggle not reversible: '+id);
  }
  const beforeCulling=await fingerprint();
  await page.$eval('#cull-cars',e=>{e.checked=true;e.dispatchEvent(new Event('input'))});
  if(await fingerprint()!==beforeCulling) throw Error('Culling changed demo pixels');
  await page.$eval('#cull-cars',e=>{e.checked=false;e.dispatchEvent(new Event('input'))});
  if(await fingerprint()!==beforeCulling) throw Error('Culling toggle failed to restore batch');
  // Deterministic host-time injection; no performance claim from these deltas.
  const still=await fingerprint();
  await page.evaluate(()=>softgfxAdvance(.02));
  let motion=await page.evaluate(()=>softgfxTiming());
  if(motion.simulationTicks!==0 || Math.abs(motion.renderAlpha-.4)>1e-6)
   throw Error('Fixed clock did not retain fractional time');
  if(await fingerprint()!==still)throw Error('Motion before first simulation snapshot');
  await page.evaluate(()=>softgfxAdvance(.03));
  if(await fingerprint()!==still)throw Error('Previous/current interpolation lag changed');
  await page.evaluate(()=>softgfxAdvance(.025));
  const halfStep=await fingerprint();
  if(halfStep===still)throw Error('Interpolated midpoint did not change pixels');
  await page.evaluate(()=>softgfxAdvance(5));
  motion=await page.evaluate(()=>softgfxTiming());
  if(motion.simulationTicks!==1 || motion.renderAlpha!==0 || motion.droppedSimulationSeconds<5)
   throw Error('Long pause advanced simulation');
  if(await fingerprint()!==halfStep)throw Error('Long pause changed displayed pose');
  await page.evaluate(()=>softgfxAdvance(.25));
  motion=await page.evaluate(()=>softgfxTiming());
  if(motion.simulationTicks!==5 || motion.droppedSimulationSeconds<5.07)
   throw Error('Catch-up exceeded fixed-step budget or failed to report dropped time');
  const beforeInput=await fingerprint();
  const box=await page.$eval('canvas',c=>{const r=c.getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height}});
  await page.mouse.move(box.x+box.w/2,box.y+box.h/2);
  await page.mouse.down();
  await page.mouse.move(box.x+box.w/2+100,box.y+box.h/2,{steps:15});
  await page.mouse.up();
  const afterDrag=await fingerprint();
  if(beforeInput===afterDrag) throw Error('Camera drag had no effect');
  await page.mouse.wheel({deltaY:150});
  await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
  let afterZoom=await fingerprint();
  if(afterZoom===afterDrag) throw Error('Zoom had no effect');
  await page.evaluate(()=>{
   const gl=document.querySelector('canvas').getContext(new URLSearchParams(location.search).has('webgl1')?'webgl':'webgl2');
   globalThis.uploads=[]; globalThis.geometryUploads=0; globalThis.indexedDraws=0;
   globalThis.instanceUploads=[]; globalThis.streamViews=new Set();
   const update=gl.bufferSubData.bind(gl);
   gl.bufferSubData=(...args)=>{
    globalThis.instanceUploads.push({target:args[0],bytes:args[2].byteLength});
    globalThis.streamViews.add(args[2]);return update(...args);
   };
   const sub=gl.texSubImage2D.bind(gl), buffer=gl.bufferData.bind(gl), draw=gl.drawElements.bind(gl);
   gl.texSubImage2D=(...args)=>{globalThis.uploads.push({w:args[4],h:args[5],format:args[6],bytes:args[8].byteLength});return sub(...args)};
   gl.bufferData=(...args)=>{globalThis.geometryUploads++;return buffer(...args)};
   gl.drawElements=(...args)=>{globalThis.indexedDraws++;return draw(...args)};
  });
  await page.click('#step-cars');
  await page.click('#step-cars');
  const stepped=await fingerprint();
  if(stepped===afterZoom) throw Error('Instance poses did not change image');
  afterZoom=stepped;
  await page.evaluate(()=>{
   const mode=document.getElementById('batch-mode').textContent;
   const expected=mode==='fallbackDraws'?0:2;
   if(globalThis.instanceUploads.length!==expected || globalThis.geometryUploads!==0)
    throw Error('Unexpected instance update allocation');
   for(const upload of globalThis.instanceUploads)
    if(upload.bytes!==108 || upload.target!==0x8892) throw Error('Bad instance payload');
   if(globalThis.streamViews.size!==(expected?1:0)) throw Error('Float32Array view not reused');
   const calls=1+(mode==='fallbackDraws'?4:2)+(new URLSearchParams(location.search).has('webgl1')?0:1);
   if(!document.getElementById('batch-stats').textContent.startsWith(String(calls)))
    throw Error('Draw-call budget mismatch');
   if(new URLSearchParams(location.search).has('fallback') && mode!=='fallbackDraws')
    throw Error('Forced fallback ignored');
  });
  await page.click('#paint-territory');
  const beforeLoss=await fingerprint();
  if(beforeLoss===afterZoom) throw Error('Territory delta did not change pixels');
  await page.evaluate(()=>{
   const u=globalThis.uploads;
   if(u.length!==1 || u[0].bytes!==15 || u[0].w!==3 || u[0].h!==5 ||
      u[0].format!==(new URLSearchParams(location.search).has('webgl1')?0x1909:0x1903) || globalThis.geometryUploads!==0 || globalThis.indexedDraws===0)
    throw Error('Delta/indexed path contract violated: '+JSON.stringify(u));
  });
  await page.evaluate(()=>{
   const gl=document.querySelector('canvas').getContext(new URLSearchParams(location.search).has('webgl1')?'webgl':'webgl2');
   globalThis.lose=gl.getExtension('WEBGL_lose_context');
   if(!globalThis.lose) throw Error('Context-loss extension missing in test driver');
   globalThis.lose.loseContext();
  });
  await page.waitForFunction(()=>document.querySelector('#status').textContent==='lost');
  if(!await page.evaluate(()=>globalThis.softgfxRetiredHandlesRejected())) throw Error('Lost handles still usable');
  await page.evaluate(()=>globalThis.lose.restoreContext());
  await page.waitForFunction(()=>document.querySelector('#status').textContent.startsWith('webgl'));
  if(!await page.evaluate(()=>globalThis.softgfxRetiredHandlesRejected())) throw Error('Restore revived stale handles');
  if(await fingerprint()!==beforeLoss) throw Error('Context restore changed image');
  await page.evaluate(()=>globalThis.lose.loseContext());
  await page.waitForFunction(()=>document.querySelector('#status').textContent==='lost');
  await page.click('#paint-territory');
  await page.click('#step-cars');
  if(!await page.evaluate(()=>globalThis.softgfxRetiredHandlesRejected())) throw Error('Lost handles still usable');
  await page.evaluate(()=>globalThis.lose.restoreContext());
  await page.waitForFunction(()=>document.querySelector('#status').textContent.startsWith('webgl'));
  if(await fingerprint()===beforeLoss) throw Error('Owner edit during context loss was lost');
  // Exercise the real RAF host, then stop before deterministic readback.
  const beforeRun=await fingerprint();
  const drawsBeforeRun=await page.evaluate(()=>globalThis.indexedDraws);
  await page.click('#run-cars');
  await page.waitForFunction(n=>globalThis.indexedDraws>n+10,{},drawsBeforeRun);
  await page.click('#run-cars');
  if(await fingerprint()===beforeRun) throw Error('RAF animation did not advance');
  if(errors.length) throw Error(errors.join('\n'));
  await page.screenshot({fullPage:true,path:`build/${result.api}${suffix.includes("fallback")?"-fallback":""}.png`});
  console.log(result); await page.close();
 }
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
