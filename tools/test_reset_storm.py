"""A fourth simulated reset must terminate, not spin or silently continue."""
import subprocess
import sys
result = subprocess.run([sys.argv[1], '--smoke', '--reset-storm', '--'+sys.argv[2]],
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=50)
print(result.stdout, end='')
assert result.returncode != 0, 'Reset storm unexpectedly succeeded'
assert 'RECOVERY LIMIT: attempts=3 cleanup=abandon' in result.stdout
assert 'Automatic context recovery budget exhausted' in result.stdout
print('RESET STORM PASS: bounded failure after three recoveries (simulated loss)')
