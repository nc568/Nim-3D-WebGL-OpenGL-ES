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
