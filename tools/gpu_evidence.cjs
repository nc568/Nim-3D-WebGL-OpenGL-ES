const fs=require('fs'),assert=require('assert/strict'),{execFileSync}=require('child_process');
function command(file,args) {
 try {return {available:true,output:execFileSync(file,args,{encoding:'utf8',timeout:15000,maxBuffer:1024*1024}).trim()};}
 catch {return {available:false,output:null};}
}
function inventory() {
 const result={platform:process.platform,arch:process.arch,devices:[],probeAvailable:false};
 if(process.platform==='darwin') {
  const probe=command('system_profiler',['SPDisplaysDataType','-json']);
  if(probe.available) {
   try {
    const data=JSON.parse(probe.output).SPDisplaysDataType;
    if(Array.isArray(data)) {
     result.probeAvailable=true;
     result.devices=data.map(d=>{
      const out={};
      for(const key of ['sppci_model','spdisplays_vendor','spdisplays_metal','spdisplays_vram','spdisplays_cores'])
       if(typeof d[key]==='string')out[key]=d[key].slice(0,512);
      return out;
     });
    }
   } catch {}
  }
 } else if(process.platform==='linux') {
  result.drmNodes=fs.existsSync('/dev/dri')?fs.readdirSync('/dev/dri').filter(n=>/^(card|renderD)\d+$/.test(n)):[];
  const probe=command('nvidia-smi',['--query-gpu=name,driver_version','--format=csv,noheader']);
  result.nvidia=probe.available?probe.output.slice(0,4096):null;
  result.probeAvailable=probe.available||result.drmNodes.length>0;
 }
 return result;
}
function classify(renderer) {
 if(/swiftshader|llvmpipe|softpipe|software rasterizer/i.test(renderer))return 'software-indicated';
 if(/apple\s*(?:m\d|gpu)|nvidia|radeon|intel.*(?:iris|uhd|hd graphics)/i.test(renderer))return 'hardware-indicated-unverified';
 return 'unknown';
}
function validateTimer(r) {
 for(const kind of ['cpu','gpu']) {
  const n=r[kind+'Samples'],median=r[kind+'MedianMs'],p95=r[kind+'P95Ms'];
  assert(Number.isInteger(n)&&n>=0);
  if(n===0){assert.equal(median,null);assert.equal(p95,null);}
  else {assert(Number.isFinite(median)&&median>=0);assert(Number.isFinite(p95)&&p95>=median);}
 }
 assert(r.cpuSamples>=41);
 if(!r.gpuSupported)assert.equal(r.gpuSamples,0);
}
async function collect(browser,engine) {
 const sha=command('git',['rev-parse','HEAD']);
 const report={schemaVersion:1,engine,version:await browser.version(),revision:sha.output,
  host:inventory(),forcedSoftware:process.env.LIBGL_ALWAYS_SOFTWARE==='1',
  verifiedPhysicalGpu:false,scope:'Driver-reported evidence, not hardware acceptance or FPS',passed:false,cases:[]};
 const page=await browser.newPage();page.setDefaultTimeout(60000);
 const errors=[];page.on('pageerror',e=>errors.push(String(e)));
 try {
  for(const legacy of [false,true]) {
   await page.goto('http://127.0.0.1:8080/'+(legacy?'?webgl1':''));
   await page.waitForFunction(()=>typeof softgfxTiming==='function');
   const graphics=await page.evaluate(legacy=>{
    const gl=document.querySelector('canvas').getContext(legacy?'webgl':'webgl2');
    if(!gl)throw Error('Expected context unavailable');
    const debug=gl.getExtension('WEBGL_debug_renderer_info');
    const info={api:legacy?'webgl1':'webgl2',vendor:gl.getParameter(gl.VENDOR),renderer:gl.getParameter(gl.RENDERER),
      version:gl.getParameter(gl.VERSION),unmaskedVendor:debug?gl.getParameter(debug.UNMASKED_VENDOR_WEBGL):null,
      unmaskedRenderer:debug?gl.getParameter(debug.UNMASKED_RENDERER_WEBGL):null};
    gl.finish=()=>{throw Error('Blocking finish in profiler')};
    gl.readPixels=()=>{throw Error('Readback in profiler')};
    const ext=gl.getExtension(legacy?'EXT_disjoint_timer_query':'EXT_disjoint_timer_query_webgl2');
    if(ext) {
     const owner=legacy?ext:gl,readName=legacy?'getQueryObjectEXT':'getQueryParameter',beginName=legacy?'beginQueryEXT':'beginQuery';
     const read=owner[readName].bind(owner),begin=owner[beginName].bind(owner),available=new Set();
     owner[beginName]=(target,q)=>{available.delete(q);return begin(target,q)};
     owner[readName]=(q,key)=>{
      if(key===0x8867){const yes=read(q,key);if(yes)available.add(q);else available.delete(q);return yes;}
      if(key===0x8866&&!available.has(q))throw Error('Read of unavailable query');
      return read(q,key);
     };
    }
    return info;
   },legacy);
   await page.click('#measure-timing');
   await page.waitForFunction(()=>softgfxTiming().frames>=100);
   await page.click('#measure-timing');
   const timing=await page.evaluate(()=>softgfxTiming());
   validateTimer(timing);assert.equal(timing.api,graphics.api);
   const renderer=graphics.unmaskedRenderer||graphics.renderer||'';
   const row={...graphics,classification:classify(renderer),timerStatus:!timing.gpuSupported?'unsupported':timing.gpuSamples?'samples-observed':'supported-no-valid-samples',timing};
   report.cases.push(row);
   const message=JSON.stringify({engine,api:row.api,renderer,classification:row.classification,timer:row.timerStatus,gpuSamples:timing.gpuSamples});
   console.log('::notice title=GPU execution evidence::'+message.replaceAll('%','%25').replaceAll('\r','%0D').replaceAll('\n','%0A'));
  }
  assert.deepEqual(errors,[]);report.passed=true;
 } catch(e){report.error=String(e);throw e;}
 finally {fs.writeFileSync(`build/gpu-evidence-${engine}.json`,JSON.stringify(report,null,2));await page.close();}
 return report;
}
module.exports={collect,classify,validateTimer};
