const assert=require('assert/strict');
const {validate,medians}=require('../tools/percentile_report.cjs');
const series=()=>({rawMs:Array.from({length:41},(_,i)=>40-i),medianMs:20,p95Ms:38});
const valid={schemaVersion:1,warmup:20,samples:41,framesPerSample:1024,readsPerFrame:2,
 rows:[0,1,2].map(pattern=>({pattern,checksum:123,ordered:series(),sortReference:series()}))};
assert.equal(validate(valid),valid);assert.equal(medians(valid).length,3);
for(const change of [r=>r.schemaVersion=2,r=>r.warmup=0,r=>r.samples=40,
 r=>r.framesPerSample=1,r=>r.readsPerFrame=1,r=>r.rows.pop(),r=>r.rows[1].pattern=0,
 r=>r.rows[0].checksum=NaN,r=>r.rows[0].checksum=0,
 r=>r.rows[0].ordered.rawMs.pop(),r=>r.rows[0].ordered.medianMs=21,
 r=>r.rows[0].sortReference.p95Ms=39,r=>r.rows[0].ordered.rawMs[0]=Infinity,
 r=>r.rows[0].ordered.rawMs[0]=-1,r=>r.rows[0].sortReference.rawMs[0]=null]) {
 const report=structuredClone(valid);change(report);assert.throws(()=>validate(report));
}
const zero=structuredClone(valid);
for(const r of zero.rows)for(const key of ['ordered','sortReference'])r[key]={rawMs:Array(41).fill(0),medianMs:0,p95Ms:0};
validate(zero); // Clock quantization can yield zero; never invent a speedup ratio.
assert.deepEqual(valid.rows[0].ordered.rawMs,Array.from({length:41},(_,i)=>40-i));
console.log('Paired CPU evidence schema / quantiles / invalid timings / zero duration PASS');
