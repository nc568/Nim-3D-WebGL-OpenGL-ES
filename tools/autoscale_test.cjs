// SYNTHETIC GPU durations for deterministic host/controller integration.
// This test makes NO performance claim about the software GPU.
const {default: chromium, inflate}=require('@sparticuz/chromium');
const puppeteer=require('puppeteer-core');
(async()=>{
 if(process.env.USE_BUNDLED_LIBS==='1') {
  const dir=await inflate(require('path').join(__dirname,'../node_modules/@sparticuz/chromium/bin/al2023.tar.br'));
  process.env.LD_LIBRARY_PATH=dir+'/lib:'+(process.env.LD_LIBRARY_PATH||'');
 }
 const browser=await puppeteer.launch({executablePath:await chromium.executablePath(),args:chromium.args,headless:true});
 try {
  const page=await browser.newPage();const errors=[];
  page.on('pageerror',e=>errors.push(String(e)));
  await page.goto('http://127.0.0.1:8080/');
  await page.waitForFunction(()=>typeof softgfxTiming==='function');
  await page.evaluate(()=>{
   const canvas=document.querySelector('canvas');canvas.width=64;canvas.height=64;
   const gl=canvas.getContext('webgl2');globalThis.testGl=gl;
   globalThis.syntheticNs=30000000;globalThis.syntheticDisjoint=false;
   const query=gl.getQueryParameter.bind(gl),param=gl.getParameter.bind(gl);
   gl.getQueryParameter=(q,k)=>k===0x8867?true:k===0x8866?syntheticNs:query(q,k);
   gl.getParameter=k=>k===0x8FBB?syntheticDisjoint:param(k);
   if(!softgfxTiming().gpuSupported)throw Error('Fixture needs timer extension');
   const e=document.getElementById('auto-scale');e.checked=true;e.dispatchEvent(new Event('input'));
  });
  await page.waitForFunction(()=>softgfxTiming().scale<.99,{timeout:30000});
  let report=await page.evaluate(()=>softgfxTiming());
  if(Math.abs(report.scale-.95)>.001||report.renderWidth!==61)throw Error('Scale not applied to FBO');
  await page.evaluate(()=>{globalThis.syntheticNs=5000000});
  await page.waitForFunction(()=>softgfxTiming().scale>.99,{timeout:30000});
  await page.evaluate(()=>{globalThis.syntheticDisjoint=true;globalThis.syntheticNs=100000000});
  await page.evaluate(async()=>{for(let i=0;i<50;i++)await new Promise(requestAnimationFrame)});
  report=await page.evaluate(()=>softgfxTiming());
  if(report.scale!==1||report.gpuSamples!==0)throw Error('Disjoint used for scaling');
  await page.evaluate(()=>{
   globalThis.syntheticDisjoint=false;
   const e=document.getElementById('post-enabled');e.checked=false;e.dispatchEvent(new Event('input'));
  });
  report=await page.evaluate(()=>softgfxTiming());
  if(report.autoActive||report.scale!==1)throw Error('Autoscale active on direct path');
  await page.evaluate(()=>{
   const e=document.getElementById('post-enabled');e.checked=true;e.dispatchEvent(new Event('input'));
   globalThis.loss=testGl.getExtension('WEBGL_lose_context');loss.loseContext();
  });
  await page.waitForFunction(()=>document.getElementById('status').textContent==='lost');
  report=await page.evaluate(()=>softgfxTiming());
  if(report.autoActive||report.gpuSamples)throw Error('Auto survived lost GPU as active');
  if(!report.contextLost || report.instanceMode!==null)throw Error('Lost-context diagnostics accessed a retired renderer');
  await page.evaluate(()=>{globalThis.syntheticNs=16000000;loss.restoreContext()});
  await page.waitForFunction(()=>document.getElementById('status').textContent==='webgl2');
  await page.waitForFunction(()=>softgfxTiming().frames>=35);
  if((await page.evaluate(()=>softgfxTiming())).scale!==1)throw Error('Restore reused slow evidence');
  if(await page.evaluate(()=>testGl.getError()))throw Error('GL error');
  if(errors.length)throw Error(errors.join('\n'));
  await page.close();
  console.log('SYNTHETIC autoscale: down/up, FBO dimensions, disjoint, direct path, restore PASS');
 } finally {await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
