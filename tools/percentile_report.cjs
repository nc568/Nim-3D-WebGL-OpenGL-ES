// One report contract for native and browser paired CPU measurements.
const assert=require('assert/strict');
function validate(report) {
 assert.equal(report.schemaVersion,1);
 assert.equal(report.warmup,20);assert.equal(report.samples,41);
 assert.equal(report.framesPerSample,1024);assert.equal(report.readsPerFrame,2);
 assert.deepEqual(report.rows.map(r=>r.pattern),[0,1,2]);
 for(const row of report.rows) {
  assert(Number.isFinite(row.checksum)&&row.checksum>0);
  for(const key of ['ordered','sortReference']) {
   const s=row[key];assert.equal(s.rawMs.length,41);
   assert(s.rawMs.every(v=>Number.isFinite(v)&&v>=0));
   const sorted=[...s.rawMs].sort((a,b)=>a-b);
   assert.equal(s.medianMs,sorted[20]);assert.equal(s.p95Ms,sorted[38]);
  }
 }
 return report;
}
function medians(report) {
 return report.rows.map(r=>({pattern:r.pattern,orderedMedianMs:r.ordered.medianMs,sortMedianMs:r.sortReference.medianMs}));
}
module.exports={validate,medians};
if(require.main===module) {
 const fs=require('fs');
 const report={schemaVersion:1,platform:process.platform,arch:process.arch,
  scope:'Native CPU update + two percentile reads; 1024 frames/batch; NOT GPU/FPS or cross-machine ranking',compilers:[]};
 for(const compiler of ['gcc','llvm','qbe']) {
  const lines=fs.readFileSync(`build/ci-bench-${compiler}.log`,'utf8').split(/\r?\n/).filter(s=>s.startsWith('PERCENTILE_BENCH '));
  assert.equal(lines.length,1,compiler+' must produce exactly one percentile report');
  const data=validate(JSON.parse(lines[0].slice('PERCENTILE_BENCH '.length)));
  report.compilers.push({compiler,...data});
  console.log('::notice title=Native percentile CPU evidence::'+JSON.stringify({compiler,framesPerSample:data.framesPerSample,rows:medians(data)}));
 }
 fs.writeFileSync('build/percentile-native.json',JSON.stringify(report,null,2));
 console.log('Native paired percentile report PASS: GCC / LLVM / QBE');
}
