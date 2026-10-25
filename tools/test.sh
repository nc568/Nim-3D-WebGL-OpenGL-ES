#!/bin/sh
set -eu
NIM=${NIM:-nim}
mkdir -p build
"$NIM" c --nimcache:build/cache-gcc -r -o:build/test_core tests/test_core.nim
"$NIM" js -o:build/test_core.js tests/test_core.nim
node build/test_core.js
"$NIM" c --nimcache:build/cache-math -r -o:build/test_math3d tests/test_math3d.nim
"$NIM" js -o:build/test_math3d.js tests/test_math3d.nim
node build/test_math3d.js
"$NIM" c --nimcache:build/cache-resources -r -o:build/test_resources tests/test_resources.nim
"$NIM" js -o:build/test_resources.js tests/test_resources.nim
node build/test_resources.js
"$NIM" c --nimcache:build/cache-instances -r -o:build/test_instances tests/test_instances.nim
"$NIM" js -o:build/test_instances.js tests/test_instances.nim
node build/test_instances.js
"$NIM" c --nimcache:build/cache-post -r -o:build/test_post tests/test_post.nim
"$NIM" js -o:build/test_post.js tests/test_post.nim
node build/test_post.js
"$NIM" c --nimcache:build/cache-timing -r -o:build/test_timing tests/test_timing.nim
"$NIM" js -o:build/test_timing.js tests/test_timing.nim
node build/test_timing.js
node tools/check_js_hotpath.cjs build/test_timing.js scopes
"$NIM" c --nimcache:build/cache-autoscale -r -o:build/test_autoscale tests/test_autoscale.nim
"$NIM" js -o:build/test_autoscale.js tests/test_autoscale.nim
node build/test_autoscale.js
"$NIM" c --nimcache:build/cache-environment -r -o:build/test_environment tests/test_environment.nim
"$NIM" js -o:build/test_environment.js tests/test_environment.nim
node build/test_environment.js
"$NIM" c --nimcache:build/cache-culling -r -o:build/test_culling tests/test_culling.nim
"$NIM" js -o:build/test_culling.js tests/test_culling.nim
node build/test_culling.js
"$NIM" c --nimcache:build/cache-motion -r -o:build/test_motion tests/test_motion.nim
"$NIM" js -o:build/test_motion.js tests/test_motion.nim
node build/test_motion.js
"$NIM" c --nimcache:build/cache-dirty -r -o:build/test_dirty tests/test_dirty.nim
"$NIM" js -o:build/test_dirty.js tests/test_dirty.nim
node build/test_dirty.js
node tools/check_js_hotpath.cjs build/test_dirty.js packing
"$NIM" c --nimcache:build/cache-identity -r -o:build/test_identity tests/test_identity.nim
"$NIM" js -o:build/test_identity.js tests/test_identity.nim
node build/test_identity.js
node tools/check_js_hotpath.cjs build/test_identity.js identity
"$NIM" c --nimcache:build/cache-grid -r -o:build/test_grid tests/test_grid.nim
"$NIM" js -o:build/test_grid.js tests/test_grid.nim
node build/test_grid.js
"$NIM" c --nimcache:build/cache-recovery -r -o:build/test_recovery tests/test_recovery.nim
"$NIM" js -o:build/test_recovery.js tests/test_recovery.nim
node build/test_recovery.js
node tools/check_js_hotpath.cjs build/test_recovery.js recovery
"$NIM" c --nimcache:build/cache-workloads -r -o:build/test_workloads tests/test_workloads.nim
"$NIM" js -o:build/test_workloads.js tests/test_workloads.nim
node build/test_workloads.js
node tools/check_js_hotpath.cjs build/test_workloads.js grid
"$NIM" js -o:build/test_webgl.js tests/test_webgl.nim
node tools/check_js_hotpath.cjs build/test_webgl.js culling
printf '<!doctype html><canvas id="scene" width="64" height="64"></canvas><p id="status">RUNNING</p><script src="test_webgl.js"></script>' > build/gpu-test.html
"$NIM" js -d:release -o:build/browser.js examples/browser.nim
node tools/check_js_hotpath.cjs build/browser.js
node tools/check_js_hotpath.cjs build/browser.js culling
node tools/check_js_hotpath.cjs build/browser.js motion
cp examples/index.html build/index.html
cp web/debug-recorder.js build/debug-recorder.js
if [ -n "${FOSSIL_SRC:-}" ]; then
  "$NIM" js -d:release -d:html --path:"$FOSSIL_SRC" -o:build/ui_overlay.js examples/ui_overlay.nim
  cp examples/ui.html build/ui.html
fi

node tools/check_js_hotpath.cjs build/test_webgl.js ranges

node tests/debug_recorder.cjs

"$NIM" js -d:release -o:build/bench_release.js tests/bench_release.nim
printf '<!doctype html><meta charset="utf-8"><title>CPU release workloads</title><script src="bench_release.js"></script>' > build/benchmark.html

node tests/gpu_evidence.cjs

node tools/check_js_hotpath.cjs build/test_webgl.js camera

node tools/check_js_hotpath.cjs build/test_webgl.js postcache
