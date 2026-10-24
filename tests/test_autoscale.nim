import std/math
import softgfx/[autoscale, timing]
var q = initAutoScale()
proc frame(q: var AutoScale; id: int; ms: float64): bool =
  let now = float64(id)*16
  q.submitted(id,now)
  q.observe(GpuSample(frame:id,ms:ms),now)
for i in 1..65: doAssert not q.frame(i,30)
doAssert q.frame(66,30)
doAssert abs(q.scale-0.95) < 0.0001 and q.changes == 1
for i in 67..161: doAssert not q.frame(i,30)
# 1000ms cooldown requires frames >=129; next 36 valid samples end at164.
for i in 162..163: doAssert not q.frame(i,30)
doAssert q.frame(164,30)
q = initAutoScale(0.7)
for i in 1..149: doAssert not q.frame(i,5)
doAssert q.frame(150,5)
doAssert abs(q.scale-0.75) < 0.0001
# No oscillation around target; clamps after long slow/fast runs.
q = initAutoScale()
for i in 1..500: doAssert not q.frame(i,if i mod 2 == 0: 17 else: 16)
for i in 501..2000: discard q.frame(i,30)
doAssert abs(q.scale-0.7) < 0.0001
for i in 2001..5000: discard q.frame(i,5)
doAssert q.scale == 1
# Delayed and sparse samples must not change scale, even with very high times.
q = initAutoScale()
for i in 1..300:
  q.submitted(i,float64(i)*16)
  doAssert not q.observe(GpuSample(frame:i-9,ms:100),float64(i)*16)
doAssert q.scale == 1
q = initAutoScale()
for i in 1..500:
  q.submitted(i,float64(i)*16)
  if i mod 9 == 0: doAssert not q.observe(GpuSample(frame:i,ms:30),float64(i)*16)
doAssert q.scale == 1
# Wall-clock freshness, duplicates, invalid values, reset/epoch and pause warmup.
q = initAutoScale()
for i in 1..60:
  q.submitted(i,float64(i)*16)
  discard q.observe(GpuSample(frame:i,ms:30),float64(i)*16)
  for duplicate in 1..10:
    doAssert not q.observe(GpuSample(frame:i,ms:30),float64(i)*16)
q.reset(0.85)
for i in 1..30: doAssert not q.frame(i,30)
for value in [NaN,Inf,-1.0,0.0,300.0]:
  doAssert not q.observe(GpuSample(frame:30,ms:value),480)
q.submitted(31,1000)
doAssert not q.observe(GpuSample(frame:31,ms:30),1201)
for i in 32..60:
  q.submitted(i,1000+float64(i-31)*16)
  doAssert not q.observe(GpuSample(frame:i,ms:30),1000+float64(i-31)*16)
doAssert abs(q.scale-0.85) < 0.0001
echo "GPU autoscale freshness/density/hysteresis/clamps/reset: PASS"

# Insufficient density by frame span or wall time, not just a single long gap.
for spacing in [3,1]:
  q = initAutoScale()
  for i in 1..500:
    let now = float64(i)*(if spacing == 3: 16.0 else: 100.0)
    q.submitted(i,now)
    if i mod spacing == 0:
      doAssert not q.observe(GpuSample(frame:i,ms:30),now)
# p95 guards recovery even when median is fast.
q = initAutoScale(0.7)
for i in 1..400: doAssert not q.frame(i,if i mod 12 == 0: 30 else: 5)
var empty: AutoScale
var rejected = false
try: empty.submitted(1,1)
except ValueError: rejected = true
doAssert rejected
