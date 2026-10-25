// CI integration: replay the first recorded preset through the standalone CLI,
// then compare its complete checkpoints/counters and resource balances.
const fs=require('fs'),assert=require('assert/strict'),{execFileSync}=require('child_process');
const original=JSON.parse(fs.readFileSync('build/soak-chromium.json','utf8'));
assert(original.passed);
const recipe=structuredClone(original.recipe);recipe.cases=recipe.cases.slice(0,1);
fs.writeFileSync('build/replay-input.json',JSON.stringify(recipe,null,2));
const env={...process.env,SOAK_RECIPE_FILE:'build/replay-input.json',BROWSER_ENGINE:'chromium'};
delete env.SOAK_FRAMES;delete env.SOAK_CYCLES;
execFileSync(process.execPath,['tools/run_soak.cjs'],{env,stdio:'inherit',timeout:180000});
const replay=JSON.parse(fs.readFileSync('build/replay-chromium.json','utf8'));
assert(replay.passed&&replay.replay);assert.equal(replay.cases.length,1);
assert.deepEqual(replay.cases[0],original.cases[0]);
console.log('Standalone recorded-preset replay / pixels / counters / resources PASS');
