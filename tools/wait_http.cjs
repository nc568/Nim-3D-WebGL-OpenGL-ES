// CI server readiness, bounded wait; failures propagate to the workflow.
const url = process.argv[2];
if (!url) { console.error('Usage: node tools/wait_http.cjs URL'); process.exit(2); }
(async () => {
 for (let i=0;i<40;i++) {
  try {
   const response=await fetch(url,{signal:AbortSignal.timeout(1000)});
   if(response.ok) { await response.arrayBuffer(); console.log('HTTP ready:',url); return; }
   await response.body?.cancel();
  } catch {}
  await new Promise(resolve=>setTimeout(resolve,250));
 }
 throw Error('HTTP server did not become ready: '+url);
})().catch(error=>{console.error(error);console.log('::error title=HTTP readiness::'+String(error));process.exit(1)});
