"""Strict correctness/counter report collection; timings have NO speed thresholds."""
import json
import math
import sys
from pathlib import Path
mode = sys.argv[1]
if mode == 'browser':
    names = ['ci-js.log', 'ci-browser.log']
    compilers = {'gcc', 'js'}
    apis = {'webgl1', 'webgl2'}
elif mode == 'native':
    names = ['ci-native-debug.log', 'ci-cproc-debug.log', 'ci-llvm-release.log', 'ci-qbe-release.log']
    compilers = {'gcc', 'llvm', 'qbe'}
    apis = {'gles2', 'gles3'}
else:
    raise ValueError('expected browser or native')
cpu, gpu = [], []
paths = [Path(p) for p in sys.argv[2:]] or [Path('build') / n for n in names]
for path in paths:
    for line in path.read_text().splitlines():
        if line.startswith('CPU_WORKLOAD '): cpu.append(json.loads(line[13:]))
        if line.startswith('GPU_WORKLOAD '): gpu.append(json.loads(line[13:]))
assert {r['compiler'] for r in cpu} == compilers
for compiler in compilers:
    rows = [r for r in cpu if r['compiler'] == compiler]
    assert len(rows) == 6
    assert {(r['instances'], r['dense']) for r in rows} == {(n, d) for n in (64,1024,8192) for d in (False,True)}
    for r in rows:
        assert r['unchangedSkipped'] == r['iterations'] == 12 and r['buildMode'] == 'debug'
        for k, v in r.items():
            if k.endswith('Ms'): assert math.isfinite(v) and v >= 0
        if r['dense']:
            assert r['visible'] == r['orderScans'] == r['instances'] and r['orderComparisons'] == 0
        else:
            assert r['orderScans'] == 0 and 0 < r['visible'] < r['instances']
            assert r['instanceTests'] < r['instances']//2
assert {r['api'] for r in gpu} == apis
expected_gpu = {'js'} if mode == 'browser' else compilers
assert {r['compiler'] for r in gpu} == expected_gpu
for compiler in expected_gpu:
    builds = ('debug', 'release') if compiler in ('llvm','qbe') else ('debug',)
    for build in builds:
        rows = [r for r in gpu if r['compiler'] == compiler and r['buildMode'] == build]
        assert len(rows) == 4, (compiler, build, len(rows))
        assert {(r["api"], r["forcedFallback"]) for r in rows} == {(a, f) for a in apis for f in (False,True)}
        for api in apis:
            assert sum(r['api'] == api and r['mode'] == 'fallbackDraws' for r in rows) >= 1
for r in gpu:
    assert r['instances'] == 256 and r['staticRequests'] == r['skippedUpdates'] == 32
    assert r['pixelComparisons'] == 9
    fallback = r['mode'] == 'fallbackDraws'
    assert r['savedUploadBytes'] == (0 if fallback else 32*256*36)
    assert r['drawCalls'] == (r['visible'] if fallback else int(r['visible'] > 0))
output = Path('build') / f'workload-{mode}.json'
output.write_text(json.dumps({'schemaVersion':1,
    'scope':'Correctness/counters + diagnostic CPU timings; software CI, NOT hardware FPS or full E1-E7',
    'cpu':cpu,'gpu':gpu}, indent=2)+'\n')
print('Workload report PASS:', output, len(cpu), 'CPU rows,', len(gpu), 'GPU rows')
