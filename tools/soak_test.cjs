const fs=require('fs'),assert=require('assert/strict');
const {installResourceTracker}=require('./resource_tracker.cjs');
const recipes=require('./soak_recipe.cjs');
module.exports=async function soak(browser,engine) {
 const current=recipes.identity();
 if(process.env.SOAK_RECIPE_FILE&&(process.env.SOAK_FRAMES||process.env.SOAK_CYCLES))throw Error('Do not mix recipe and frame/cycle overrides');
 const recipe=process.env.SOAK_RECIPE_FILE?recipes.load(process.env.SOAK_RECIPE_FILE,current):recipes.defaults(current,Number(process.env.SOAK_FRAMES||96),Number(process.env.SOAK_CYCLES||2));
 const {frames,cycles}=recipe;
 fs.writeFileSync(`build/soak-recipe-${engine}.json`,JSON.stringify(recipe,null,2));
 const report={schemaVersion:2,engine,version:await browser.version(),frames,cycles,recipe,
  executionRevision:current.sourceRevision,platform:process.platform,arch:process.arch,
  generator:"grid-v1 (deterministic formulas, no RNG)",
  scope:'Provisional deterministic soak; API handle balance, not driver/JS memory proof',passed:false,cases:[]};
 let cursor=null;
 const page=await browser.newPage();page.setDefaultTimeout(120000);
 const errors=[];page.on('pageerror',e=>errors.push(String(e)));
 try {
  for(const [presetIndex,preset] of recipe.cases.entries()) {
   const {count,fallback}=preset,legacy=preset.api==='webgl1';
   cursor={presetIndex,cycle:null};
   await page.goto('http://127.0.0.1:8080/soak.html'+(legacy?'?webgl1':''));
   await page.waitForFunction(()=>typeof softgfxSoak==='object');
   await page.evaluate(source=>{
    globalThis.soakTick=null;
    const gl=document.querySelector('canvas').getContext(new URLSearchParams(location.search).has('webgl1')?'webgl':'webgl2');
    if(!gl)throw Error('Expected WebGL context missing');
    globalThis.soakGL=gl;globalThis.soakTracker=(0,eval)('('+source+')')(gl);
   },installResourceTracker.toString());
   const row={legacy,count,fallback,cycles:[]};report.cases.push(row);
   for(let cycle=0;cycle<cycles;cycle++) {
    cursor={presetIndex,cycle};
    console.log('Soak cycle:',engine,legacy?'webgl1':'webgl2',count,fallback,cycle);
    const result=await page.evaluate(async ({count,fallback,frames})=>{
     const gl=soakGL,checkpoints=[];let state,firstHash;
     softgfxSoak.start(count,fallback);
     try {
      for(let tick=0;tick<frames;tick++) {
       globalThis.soakTick=tick;
       try {state=JSON.parse(softgfxSoak.step(tick));}
       catch(e){throw Error('Scenario tick '+tick+': '+String(e));}
       if(gl.getError())throw Error('GL error at tick '+tick);
       if(tick%24===0||tick===frames-1) {
        const a=new Uint8Array(192*128*4),b=new Uint8Array(a.length);
        gl.readPixels(0,0,192,128,gl.RGBA,gl.UNSIGNED_BYTE,a);
        softgfxSoak.reference();
        gl.readPixels(0,0,192,128,gl.RGBA,gl.UNSIGNED_BYTE,b);
        let hash=2166136261,opaque=0;
        for(let i=0;i<a.length;i++) {
         if(a[i]!==b[i])throw Error('Full-batch pixel mismatch tick '+tick+' byte '+i);
         hash=Math.imul(hash^a[i],16777619)>>>0;
         if(i%4===3&&a[i]===255)opaque++;
        }
        if(opaque!==192*128||gl.getError())throw Error('Invalid readback');
        if(tick===0)firstHash=hash;
        checkpoints.push({tick,hash});
       }
       // Yield between batches; this is not a paced FPS benchmark.
       if(tick%8===7)await new Promise(resolve=>setTimeout(resolve,0));
      }
      return {state,checkpoints,firstHash,steady:soakTracker.snapshot()};
     } finally {softgfxSoak.stop();}
    },{count,fallback,frames});
    const end=await page.evaluate(()=>soakTracker.snapshot());
    result.end=end;row.cycles.push(result);
    assert.equal(result.state.api,legacy?'webgl1':'webgl2');
    assert.equal(result.state.tick,frames-1);assert.equal(result.state.instances,count);
    if(fallback)assert.equal(result.state.mode,'fallbackDraws');
    assert.equal(result.state.territoryDeltas,Math.ceil(frames/12));
    assert.deepEqual(end.violations,[]);
    for(const r of end.resources){assert.equal(r.live,0,r.kind);assert.equal(r.created,r.deleted,r.kind);}
    if(cycle>0) {
     assert.deepEqual(result.checkpoints,row.cycles[0].checkpoints,'Recreation changed deterministic pixels');
     assert.deepEqual(result.state,row.cycles[0].state,'Recreation changed counters');
     assert.deepEqual(result.steady.resources.map(r=>[r.kind,r.live]),row.cycles[0].steady.resources.map(r=>[r.kind,r.live]));
    }
   }
   await page.evaluate(()=>soakTracker.restore());
  }
  assert.deepEqual(errors,[]);report.passed=true;
  report.scenarioFrames=frames*cycles*report.cases.length;
  report.oracleFrames=report.cases.reduce((total,c)=>total+c.cycles.reduce((n,cycle)=>n+cycle.checkpoints.length,0),0);
  console.log('::notice title=Soak evidence::'+JSON.stringify({engine,frames,cycles,presets:report.cases.length,scenarioFrames:report.scenarioFrames,oracleFrames:report.oracleFrames,passed:true}));
  console.log('Game-like soak PASS:',engine,report.cases.length,'presets',frames*cycles*report.cases.length,'frames');
 } catch(e){
  report.error=String(e);report.pageErrors=errors;report.cursor=cursor;
  try {report.failedTick=await page.evaluate(()=>globalThis.soakTick??null);} catch {}
  try {report.failureResources=await page.evaluate(()=>soakTracker.snapshot());} catch {}
  try {await page.screenshot({path:`build/soak-${engine}-failure.png`});} catch {}
  throw e;
 }
 finally {fs.writeFileSync(`build/soak-${engine}.json`,JSON.stringify(report,null,2));await page.close();}
};
