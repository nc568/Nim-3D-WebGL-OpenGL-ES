const vm=require('vm'),fs=require('fs'),assert=require('assert/strict');
const source=fs.readFileSync('web/debug-recorder.js','utf8');
function target() {
 const callbacks=new Map();
 return {addEventListener(n,cb){callbacks.set(n,cb)},removeEventListener(n){callbacks.delete(n)},callbacks};
}
function boot(search) {
 const window=target(),canvas=target(),document={...target(),visibilityState:'visible',
 getElementById:()=>canvas,body:{appendChild(){}},createElement:()=>({})};
 const context={location:{search},URLSearchParams,performance:{now:()=>42},window,document,navigator:{userAgent:'test'}};
 vm.runInNewContext(source,context);return {context,window,canvas,document};
}
assert.equal(boot('').context.softgfxDebug,undefined);
const {context,window,canvas}=boot('?debug'); const d=context.softgfxDebug;
for(let i=0;i<59;i++)d.frame(4,3,36,1);
assert.equal(d.snapshot().total,1);
d.frame(4,3,36,1);assert.equal(d.snapshot().events[1].kind,'frame');
window.callbacks.get('error')({message:'x'.repeat(1000)});
assert.equal(d.snapshot().events[2].message.length,512);
window.callbacks.get('unhandledrejection')({reason:{secret:'not exported'}});
assert(!JSON.stringify(d.snapshot()).includes('not exported'));
canvas.callbacks.get('webglcontextlost')();
assert.equal(d.snapshot().events.at(-1).message,'webglcontextlost');
for(let i=0;i<10000;i++)d.mark(String(i));
let s=d.snapshot();assert.equal(s.events.length,256);assert.equal(s.overwritten,s.total-256);
assert.equal(s.events.at(-1).message,'9999');s.events[0].message='mutated';
assert.notEqual(d.snapshot().events[0].message,'mutated');
d.attach({getParameter:()=>42,getSupportedExtensions:()=>['test']},'webgl2');
assert.equal(d.snapshot().graphics.api,'webgl2');
const caps=d.snapshot();caps.graphics.extensions[0]='mutated';
assert.equal(d.snapshot().graphics.extensions[0],'test');
context.softgfxTiming=()=>({cpuMedianMs:2,secret:'never export',drawCalls:Infinity});
assert.equal(d.snapshot().profile.cpuMedianMs,2);
assert(!JSON.stringify(d.snapshot()).includes('never export'));
assert.equal(d.snapshot().profile.drawCalls,undefined);
context.softgfxTiming=()=>{throw Error('disposed')};
assert.equal(d.snapshot().profile.unavailable,true);
s=d.snapshot();
d.stop();d.mark('after stop');d.frame(1,1,1,1);
assert.equal(window.callbacks.size,0);assert.equal(canvas.callbacks.size,0);
assert.equal(d.snapshot().total,s.total);assert.equal(d.snapshot().frames,s.frames);
console.log('Bounded opt-in diagnostic recorder / sampling / stop / export isolation PASS');
const b=boot('?debug').context.softgfxDebug;
b.setBudgets({drawCalls:4,uploadBytes:36});
b.frame(4,1,100,0); // baseline, NOT a 100-byte frame
assert.equal(b.snapshot().budgetStatus.mask,0);
b.frame(4,1,136,0); // equality is within budget
assert.equal(b.snapshot().budgetStatus.mask,0);
b.frame(5,1,173,0);
assert.equal(b.snapshot().budgetStatus.mask,3);
const before=b.snapshot().events.filter(e=>e.kind==='budget-exceeded').length;
for(let i=0;i<100;i++)b.frame(5,1,210+i*37,0);
assert.equal(b.snapshot().events.filter(e=>e.kind==='budget-exceeded').length,before);
assert.equal(b.snapshot().budgetStatus.episodes,1);
b.frame(4,1,3873,0); // previous 3873, no new upload
assert.equal(b.snapshot().budgetStatus.mask,0);
assert.equal(b.snapshot().events.at(-1).kind,'budget-recovered');
b.frame(4,1,0,0); // counter reset cannot be negative upload
assert.equal(b.snapshot().budgetStatus.unknownFrames,2);
b.frame(4,1,2147483647,0);
assert.equal(b.snapshot().budgetStatus.unknownFrames,3);
assert.throws(()=>b.setBudgets({drawCalls:1,uploadBytes:-1}));
assert.equal(b.snapshot().budgets.drawCalls,4); // atomic validation
const snapshot=b.snapshot();snapshot.budgets.drawCalls=99;
assert.equal(b.snapshot().budgets.drawCalls,4);
b.setBudgets(null); b.frame(999,1,999,0);
assert.equal(b.snapshot().budgetStatus.breachFrames,0);
console.log('Debug budgets / deltas / coalescing / reset / saturation PASS');
const captureBoot=boot('?debug'),c=captureBoot.context.softgfxDebug;
captureBoot.context.softgfxTiming=()=>({cpuMedianMs:2,animated:false,simulationTicks:7});
captureBoot.document.getElementById=id=>id==='post-enabled'?{type:'checkbox',checked:true}:id==='post-scale'?{type:'range',valueAsNumber:0.8}:null;
const first=c.capture('first');
const value=c.getCapture(first);
assert.equal(value.settings.controls['post-enabled'],true);
assert.equal(value.settings.controls['post-scale'],0.8);
assert.equal(value.diagnostics.profile.simulationTicks,7);
value.diagnostics.profile.cpuMedianMs=999;value.settings.controls['post-enabled']=false;
assert.equal(c.getCapture(first).diagnostics.profile.cpuMedianMs,2);
assert.equal(c.getCapture(first).settings.controls['post-enabled'],true);
captureBoot.context.softgfxTiming=()=>({cpuMedianMs:8});
assert.equal(c.getCapture(first).diagnostics.profile.cpuMedianMs,2);
for(let i=0;i<4;i++)c.capture('x'.repeat(200));
assert.equal(c.captures().length,4);assert.equal(c.getCapture(first),null);
assert.equal(c.captures()[0].label.length,96);
const list=c.captures();list[0].label='changed';assert.notEqual(c.captures()[0].label,'changed');
assert.throws(()=>c.downloadCapture(first));
const last=c.captures().at(-1).id;
c.stop();assert.throws(()=>c.capture('after stop'));
assert(c.getCapture(last));assert.equal(c.snapshot().stopped,true);
console.log('Bounded diagnostic captures / settings allowlist / isolation / eviction / stop PASS');
