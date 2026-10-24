"""Validate all compiler/API reports; missing GPU measurements stay null, not zero."""
import json
import math
from pathlib import Path
reports = []
robustChecks = []
for compiler in ('gcc', 'llvm', 'qbe'):
    for api in ('gles2', 'gles3'):
        for variant in ('', 'desktop-', 'robust-'):
            path = Path(f'build/ci-window-{variant}{compiler}-{api}.log')
            found = [json.loads(line[len('NATIVE_REPORT '):]) for line in path.read_text().splitlines()
                     if line.startswith('NATIVE_REPORT ')]
            if variant == 'robust-' and not found:
                unavailable = [json.loads(line[len('ROBUST_UNAVAILABLE '):]) for line in path.read_text().splitlines()
                               if line.startswith('ROBUST_UNAVAILABLE ')]
                assert len(unavailable) == 1 and unavailable[0]['status'] == 'unavailable'
                assert unavailable[0]['requestedApi'] == int(api[-1])
                robustChecks.append(dict(compiler=compiler, api=api, **unavailable[0]))
                continue
            assert len(found) == 2, (path, 'expected two complete sessions')
            if variant == 'robust-':
                robustChecks.append(dict(compiler=compiler, api=api, status='supported'))
            for report in found:
                assert report['schemaVersion'] == 1 and report['testMode']
                assert report['api'].startswith('OpenGL ES '+api[-1]+'.')
                assert report['renderer'] and report['observedDriverResets'] == 0
                assert report['recoveryAttempts'] == report['injectedLosses'] <= 3
                assert report['warmupFrames'] == 30
                expected = min(120, max(0, report['framesInLastContext']-30))
                assert report['cpuSubmit']['samples'] == expected and report['swapWait']['samples'] == expected
                if not report['gpuTimerSupported']: assert report['gpuElapsed']['samples'] == 0
                if variant != 'desktop-':
                    assert report['recreations'] == 3 and report['injectedLosses'] == 1
                    assert report['cpuSubmit']['samples'] > 0
                if variant == 'robust-':
                    assert report['robustRequested'] and report['robustAccess'] and report['resetSource'] != 'unavailable'
                    assert report['resetNotificationStrategy'] == 0x8252
                for name in ('cpuSubmit', 'gpuElapsed', 'swapWait'):
                    stats = report[name]
                    assert 0 <= stats['samples'] <= 120
                    if stats['samples'] == 0:
                        assert stats['medianMs'] is None and stats['p95Ms'] is None
                    else:
                        assert math.isfinite(stats['medianMs']) and math.isfinite(stats['p95Ms'])
                        assert 0 <= stats['medianMs'] <= stats['p95Ms']
                reports.append(dict(compiler=compiler, requestedApi=api, variant=variant or 'smoke', **report))
Path('build/native-report.json').write_text(json.dumps({
    'environment': 'CI Xvfb/Mesa software; injected loss is NOT a hardware reset',
    'timingScope': 'last context only; 30 warmup frames; rolling 120; not FPS',
    'robustContextChecks': robustChecks,
    'reports': reports}, indent=2)+'\n')
assert len(robustChecks) == 6 and len(reports) >= 24
print('Native report schema/recovery/timing validation PASS:', len(reports), 'sessions')
print('Robust context capability:', sum(c['status'] == 'supported' for c in robustChecks), '/ 6 supported; unavailable is NOT runtime validation')
