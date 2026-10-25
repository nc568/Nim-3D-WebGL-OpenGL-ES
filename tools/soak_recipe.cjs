const fs=require('fs'),path=require('path'),crypto=require('crypto');
const {execFileSync}=require('child_process');
const maxFrames=120000,maxBytes=16384;
const digest=value=>crypto.createHash('sha256').update(value).digest('hex');
function identity(root=process.cwd()) {
 let sourceRevision=null;
 try{sourceRevision=execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim();}catch{}
 const files=['tools/soak_test.cjs','tools/resource_tracker.cjs','tools/soak_recipe.cjs','tools/run_soak.cjs'];
 return {sourceRevision,bundleSha256:digest(fs.readFileSync(path.join(root,'build/browser_soak.js'))),
  runnerSha256:digest(Buffer.concat(files.map(name=>Buffer.concat([Buffer.from(name+'\0'),fs.readFileSync(path.join(root,name))]))))};
}
function keys(value,allowed) {
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(k=>!allowed.includes(k))||allowed.some(k=>!Object.hasOwn(value,k)))throw Error('Invalid recipe object keys');
}
function validate(value,current) {
 keys(value,['schemaVersion','generator','sourceRevision','bundleSha256','runnerSha256','frames','cycles','cases']);
 if(value.schemaVersion!==1||value.generator!=='grid-v1')throw Error('Unsupported recipe version/generator');
 if(value.sourceRevision!==null && !/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(value.sourceRevision))throw Error('Invalid source revision');
 for(const key of ['bundleSha256','runnerSha256']){
  if(typeof value[key]!=='string'||!/^[a-f0-9]{64}$/.test(value[key]))throw Error('Invalid recipe code fingerprint');
  if(current&&value[key]!==current[key])throw Error('Recipe code fingerprint mismatch: '+key);
 }
 if(!Number.isInteger(value.frames)||value.frames<48||value.frames>10000||
    !Number.isInteger(value.cycles)||value.cycles<2||value.cycles>100)throw Error('Invalid recipe frame/cycle budget');
 if(!Array.isArray(value.cases)||value.cases.length<1||value.cases.length>12||value.frames*value.cycles*value.cases.length>maxFrames)throw Error('Recipe exceeds total frame/case budget');
 const seen=new Set(),cases=[];
 for(const c of value.cases){
  keys(c,['api','count','fallback']);
  if(!['webgl1','webgl2'].includes(c.api)||![64,256,1024].includes(c.count)||typeof c.fallback!=='boolean')throw Error('Invalid recipe preset');
  const key=JSON.stringify([c.api,c.count,c.fallback]);
  if(seen.has(key))throw Error('Duplicate recipe preset');seen.add(key);
  cases.push({api:c.api,count:c.count,fallback:c.fallback});
 }
 return {schemaVersion:1,generator:'grid-v1',sourceRevision:value.sourceRevision,
  bundleSha256:value.bundleSha256,runnerSha256:value.runnerSha256,frames:value.frames,cycles:value.cycles,cases};
}
function defaults(current,frames=96,cycles=2){
 const cases=[];
 for(const api of ['webgl2','webgl1'])for(const count of [64,256,1024])for(const fallback of [false,true])cases.push({api,count,fallback});
 return validate({schemaVersion:1,generator:'grid-v1',...current,frames,cycles,cases},current);
}
function load(file,current){
 const stat=fs.statSync(file);
 if(!stat.isFile()||stat.size>maxBytes)throw Error('Recipe must be a regular JSON file <=16 KiB');
 let value;try{value=JSON.parse(fs.readFileSync(file,'utf8'));}catch{throw Error('Invalid soak recipe JSON');}
 return validate(value,current);
}
module.exports={identity,validate,defaults,load,maxFrames};
