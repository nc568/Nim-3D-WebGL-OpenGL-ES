const assert=require('assert/strict'),{classify,validateTimer}=require('../tools/gpu_evidence.cjs');
assert.equal(classify('ANGLE (NVIDIA, SwiftShader Device)'), 'software-indicated');
assert.equal(classify('llvmpipe (LLVM 18)'), 'software-indicated');
assert.equal(classify('Apple M2'), 'hardware-indicated-unverified');
assert.equal(classify('WebKit WebGL'), 'unknown');
const good={cpuSamples:70,cpuMedianMs:1,cpuP95Ms:2,gpuSamples:0,gpuMedianMs:null,gpuP95Ms:null,gpuSupported:false};
validateTimer(good);
assert.throws(()=>validateTimer({...good,gpuMedianMs:0}));
assert.throws(()=>validateTimer({...good,cpuP95Ms:NaN}));
assert.throws(()=>validateTimer({...good,gpuSamples:2,gpuMedianMs:1,gpuP95Ms:2}));
validateTimer({...good,gpuSupported:true}); // support does not guarantee a valid sample
validateTimer({...good,gpuSupported:true,gpuSamples:2,gpuMedianMs:0,gpuP95Ms:0});
console.log('GPU evidence classification / missing-vs-zero timer semantics PASS');
