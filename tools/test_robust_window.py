"""Strict capability probe: supported runtime test OR explicit refusal, never fallback."""
import json
import subprocess
import sys
result = subprocess.run([sys.argv[1], '--smoke', '--robust', '--'+sys.argv[2]],
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=50)
print(result.stdout, end='')
if result.returncode == 77:
    unavailable = [json.loads(line[len('ROBUST_UNAVAILABLE '):]) for line in result.stdout.splitlines()
                   if line.startswith('ROBUST_UNAVAILABLE ')]
    assert len(unavailable) == 1 and unavailable[0]['status'] == 'unavailable'
    assert 'Actual GLES robustness unavailable:' in unavailable[0]['reason']
    assert 'NATIVE_REPORT ' not in result.stdout, 'Strict request silently fell back'
    print('ROBUST UNAVAILABLE: driver did not provide verified reset notification; no fallback')
else:
    assert result.returncode == 0, 'Unexpected robust window failure'
    reports = [json.loads(line[len('NATIVE_REPORT '):]) for line in result.stdout.splitlines()
               if line.startswith('NATIVE_REPORT ')]
    assert len(reports) == 2
    assert all(r['robustAccess'] and r['resetNotificationStrategy'] == 0x8252 for r in reports)
    print('ROBUST WINDOW PASS: actual robust access + reset notification verified')
