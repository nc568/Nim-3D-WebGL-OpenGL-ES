// Harness orchestration only: actual browser replay remains mandatory in CI.
const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const source=fs.readFileSync('tools/check_soak_replay.cjs','utf8');
function run(failure) {
 const files=new Map(),calls=[];
 for(const [tag,frames,cycles] of [['soak',96,2],['extended',240,3]]) {
  files.set(`build/${tag}-chromium.json`,JSON.stringify({passed:true,
   recipe:{frames,cycles,cases:[{count:64},{count:256}]},
   cases:[{checkpoints:[1,2],state:{tick:frames-1}},{checkpoints:[3]}]}));
  files.set(`build/replay-${tag}-chromium.json`,'stale');
 }
 files.set('build/replay-chromium-failure.png','stale image');
 const fakeFs={readFileSync:p=>{assert(files.has(p),p);return files.get(p);},
  writeFileSync:(p,s)=>files.set(p,s),rmSync:p=>files.delete(p),existsSync:p=>files.has(p),
  renameSync:(a,b)=>{assert(files.has(a));files.set(b,files.get(a));files.delete(a);}};
 const spawn=(exe,args,options)=>{
  assert.equal(exe,process.execPath);assert.equal(args[0],'tools/run_soak.cjs');assert.equal(options.timeout,180000);
  assert(!('SOAK_FRAMES' in options.env)&&!('SOAK_CYCLES' in options.env));
  assert.equal(options.env.BROWSER_ENGINE,'chromium');
  const recipe=JSON.parse(files.get(options.env.SOAK_RECIPE_FILE));assert.equal(recipe.cases.length,1);
  const tag=recipe.frames===96?'soak':'extended';calls.push(tag);
  if(failure==='before')throw Error('startup failure');
  const original=JSON.parse(files.get(`build/${tag}-chromium.json`));
  const replay={passed:true,replay:true,cases:[original.cases[0]],scenarioFrames:recipe.frames*recipe.cycles};
  if(failure==='mismatch')replay.cases[0].checkpoints[0]=999;
  files.set('build/replay-chromium.json',JSON.stringify(replay));
  files.set('build/replay-recipe-chromium.json',JSON.stringify(recipe));
  if(failure==='after') {files.set('build/replay-chromium-failure.png','new image');throw Error('browser failure');}
 };
 const context={require:name=>name==='fs'?fakeFs:name==='child_process'?{execFileSync:spawn}:require(name),
  process:{execPath:process.execPath,env:{SOAK_FRAMES:'960',SOAK_CYCLES:'10'}},structuredClone,console:{log(){}}};
 if(failure)assert.throws(()=>vm.runInNewContext(source,context));else vm.runInNewContext(source,context);
 return {files,calls};
}
const good=run();assert.equal(good.calls.join(','),'soak,extended');
for(const [tag,frames] of [['soak',192],['extended',720]]) {
 assert.equal(JSON.parse(good.files.get(`build/replay-${tag}-chromium.json`)).scenarioFrames,frames);
 assert(good.files.has(`build/${tag}-chromium.json`));
 assert(!good.files.has(`build/replay-${tag}-chromium-failure.png`));
}
const before=run('before');assert(!before.files.has('build/replay-soak-chromium.json'));assert(!before.files.has('build/replay-extended-chromium.json'));
const after=run('after');assert(after.files.has('build/replay-soak-chromium.json'));
assert.equal(after.files.get('build/replay-soak-chromium-failure.png'),'new image');
assert(run('mismatch').files.has('build/replay-soak-chromium.json'));
console.log('Replay orchestration / both budgets / output isolation / failure retention PASS');
