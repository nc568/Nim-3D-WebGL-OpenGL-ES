// CI integration: replay the first recorded preset of BOTH workload budgets
// through the standalone CLI, comparing complete checkpoints/counters/resources.
const fs=require('fs'),assert=require('assert/strict'),{execFileSync}=require('child_process');
// Clear all previous outputs before the first attempt, even if startup fails.
for(const suffix of ['chromium.json','recipe-chromium.json','chromium-failure.png']) {
 for(const prefix of ['replay','replay-soak','replay-extended'])fs.rmSync(`build/${prefix}-${suffix}`,{force:true});
}
for(const tag of ['soak','extended']) {
 const original=JSON.parse(fs.readFileSync(`build/${tag}-chromium.json`,'utf8'));
 assert(original.passed);
 const recipe=structuredClone(original.recipe);recipe.cases=recipe.cases.slice(0,1);
 const input=`build/replay-input-${tag}.json`;
 fs.writeFileSync(input,JSON.stringify(recipe,null,2));
 const env={...process.env,SOAK_RECIPE_FILE:input,BROWSER_ENGINE:'chromium'};
 delete env.SOAK_FRAMES;delete env.SOAK_CYCLES;
 try {
  execFileSync(process.execPath,['tools/run_soak.cjs'],{env,stdio:'inherit',timeout:180000});
  const replay=JSON.parse(fs.readFileSync('build/replay-chromium.json','utf8'));
  assert(replay.passed&&replay.replay);assert.equal(replay.cases.length,1);
  assert.deepEqual(replay.cases[0],original.cases[0]);
  assert.equal(replay.scenarioFrames,recipe.frames*recipe.cycles);
  console.log('Standalone recorded-preset replay / pixels / counters / resources PASS:',tag);
 } finally {
  for(const suffix of ['chromium.json','recipe-chromium.json','chromium-failure.png']) {
   const from=`build/replay-${suffix}`;
   if(fs.existsSync(from))fs.renameSync(from,`build/replay-${tag}-${suffix}`);
  }
 }
}
