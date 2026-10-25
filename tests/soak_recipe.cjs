const assert=require('assert/strict'),fs=require('fs'),os=require('os'),path=require('path');
const {validate,defaults,load}=require('../tools/soak_recipe.cjs');
const current={sourceRevision:'a'.repeat(40),bundleSha256:'b'.repeat(64),runnerSha256:'c'.repeat(64)};
const base=defaults(current);
for(const frames of [96,240,960])for(const cycles of [2,3,10]) {
 const recipe=defaults(current,frames,cycles);assert.equal(recipe.frames,frames);assert.equal(recipe.cycles,cycles);
 assert(recipe.frames*recipe.cycles*recipe.cases.length<=120000);
}
assert.equal(base.cases.length,12);assert.equal(base.frames*base.cycles*12,2304);
const edit=fn=>{const v=structuredClone(base);fn(v);return v;};
for(const v of [edit(v=>v.extra='x'),edit(v=>v.sourceRevision=['a'.repeat(40)]),edit(v=>v.frames=NaN),edit(v=>v.cycles=1),edit(v=>v.frames=1e9),
 edit(v=>v.cases=[]),edit(v=>v.cases[0].url='https://example.com'),edit(v=>v.cases[0].fallback='false'),
 edit(v=>v.cases[0].count=65),edit(v=>v.cases[1]=v.cases[0]),edit(v=>v.generator='unknown'),
 edit(v=>v.bundleSha256='d'.repeat(64)),edit(v=>v.frames=10000)])assert.throws(()=>validate(v,current));
assert.throws(()=>validate(JSON.parse('{"__proto__": {"polluted":true}}'),current));
assert.equal({}.polluted,undefined);
const one=edit(v=>v.cases=[v.cases[0]]);assert.equal(validate(one,current).cases.length,1);
const result=validate(base,current);result.cases[0].count=256;assert.equal(base.cases[0].count,64);
// A documentation-only commit may differ: actual code hashes are authoritative.
assert.equal(validate(edit(v=>v.sourceRevision='d'.repeat(40)),current).sourceRevision,'d'.repeat(40));
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'softgfx-recipe-'));
try {
 const file=path.join(dir,'recipe.json');fs.writeFileSync(file,JSON.stringify(base));assert.deepEqual(load(file,current),base);
 fs.writeFileSync(file,' '.repeat(16385));assert.throws(()=>load(file,current));
 fs.writeFileSync(file,'not-json');assert.throws(()=>load(file,current),/Invalid soak recipe JSON/);
 assert.throws(()=>load(dir,current));
 if(process.platform!=='win32') {
  const fifo=path.join(dir,'fifo');require('child_process').execFileSync('mkfifo',[fifo]);
  // A subprocess timeout turns accidental blocking on a named pipe into failure.
  const helper=path.resolve(__dirname,'../tools/soak_recipe.cjs');
  require('child_process').execFileSync(process.execPath,['-e',
   `require('assert/strict').throws(()=>require(${JSON.stringify(helper)}).load(${JSON.stringify(fifo)}),/regular JSON file/)`],{timeout:3000});
 }

 // Short reads must not truncate JSON; a file growing after fstat is still bounded.
 fs.writeFileSync(file,JSON.stringify(base));
 const read=fs.readSync,stat=fs.fstatSync;let total=0;
 try {
  fs.readSync=(fd,b,o,n,p)=>{const result=read(fd,b,o,Math.min(n,7),p);total+=result;return result;};
  assert.deepEqual(load(file,current),base);assert(total>7);
  fs.writeFileSync(file,' '.repeat(32768));total=0;
  fs.fstatSync=fd=>({isFile:()=>true,size:1});
  assert.throws(()=>load(file,current),/exceeds 16 KiB/);assert.equal(total,16385);
 }finally{fs.readSync=read;fs.fstatSync=stat;}

}finally{fs.rmSync(dir,{recursive:true});}
console.log('Soak recipes: strict schema / code identity / bounded inputs / subsets PASS');
