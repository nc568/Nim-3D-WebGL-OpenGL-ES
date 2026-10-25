// Regression guard for pinned Nim JS codegen, not a whole-program allocation profiler.
const fs = require('fs');
const source = fs.readFileSync(process.argv[2] || 'build/browser.js', 'utf8');
const prefixes=process.argv[3]==='postcache' ? ['postUniformChanges__','retainPostUniforms__','notePostUniform__'] : process.argv[3]==='camera' ? ['submitMatrix__'] : process.argv[3]==='packing' ? ['packInstancesChanged__','packVisibleChanged__','packInstancesRange__','packVisibleRange__'] : process.argv[3]==='ranges' ? ['packInstancesRange__','packVisibleRange__','uploadInstancesRange__'] : process.argv[3]==='grid' ? ['sortIndexPrefix__','siftIndices__'] : process.argv[3]==='recovery' ? ['poll__','markLost__','consume__'] : process.argv[3]==='scopes' ? ['claim__','release__','requireAvailable__','requireContext__'] : process.argv[3]==='identity' ? ['alignHistory__','copyPose__','indexIds__','slot__'] : process.argv[3]==='motion' ? ['interpolateInstances__','blendYaw__','blend__'] : process.argv[3]==='culling' ? ['transformedInto__','intersects__','packVisibleRange__'] : ['packInstancesRange__', 'packRecordChanged__', 'storeChanged__', 'effectChanges__', 'retainEffects__', 'validate__OOZsrcZsoftgfxZinstances_', 'carSnapshot__'];
for (const prefix of prefixes) {
  const start = source.indexOf('function ' + prefix);
  if (start < 0) throw Error('Missing expected Nim hot-path function: ' + prefix);
  const end = source.indexOf('\nfunction ', start + 1);
  const body = source.slice(start, end < 0 ? undefined : end);
  if (/new (?:Float32Array|Float64Array)|nimCopy\(/.test(body)) {
    throw Error('Instance hot path regressed to object/typed-array copies: ' + prefix);
  }
}
console.log('Nim JS hot paths: no direct typed-array allocation or nimCopy:',prefixes.join(', '));
