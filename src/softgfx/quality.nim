## CPU frame-time policy, not GPU timing. Do not feed pauses/background frames.
import std/math
type
  FrameWindow* = object
    values, ordered: array[120, float32]
    count, cursor: int
  Quality* = object
    scale*: float32
    slow, fast: int

proc windowLowerBound(w: FrameWindow; count: int; value: float32): int =
  var upper = count
  while result < upper:
    let middle = (result+upper) div 2
    if w.ordered[middle] < value: result = middle+1
    else: upper = middle

proc add*(w: var FrameWindow; ms: float32; allowZero = false) =
  if ms < 0 or float64(ms) > 3.4028234663852886e38 or (ms == 0 and not allowZero) or classify(ms) in {fcNan, fcInf, fcNegInf}: return
  var count = w.count
  if count == w.values.len:
    let expired = w.values[w.cursor]
    if expired == ms:
      w.cursor = (w.cursor+1) mod w.values.len
      return # identical multiset: no shifts or reordering
    let at = windowLowerBound(w,count,expired)
    for i in at..<count-1: w.ordered[i] = w.ordered[i+1]
    dec count
  let at = windowLowerBound(w,count,ms)
  for i in countdown(count-1,at): w.ordered[i+1] = w.ordered[i]
  w.ordered[at] = ms
  w.values[w.cursor] = ms
  w.cursor = (w.cursor + 1) mod w.values.len
  w.count = count+1

proc percentiles*(w: FrameWindow): tuple[median, p95: float32] =
  ## Exact rolling order statistics, with no per-read copy/allocation/sort.
  ## add maintains a fixed-capacity sorted multiset (including duplicate values).
  if w.count == 0: return
  result.median = w.ordered[(w.count-1) div 2]
  result.p95 = w.ordered[(w.count * 95 + 99) div 100 - 1]

proc initQuality*(): Quality = Quality(scale: 1)
proc observe*(q: var Quality; ms: float32; target = 16.667'f32) =
  ## Consecutive-frame hysteresis: down after 30 slow, up after 120 fast.
  ## Long pauses (>250ms) are excluded; this is a policy prototype, not a benchmark.
  if ms <= 0 or ms > 250 or target <= 0 or
      classify(ms) in {fcNan, fcInf, fcNegInf} or
      classify(target) in {fcNan, fcInf, fcNegInf}: return
  if ms > target * 1.1:
    inc q.slow
    q.fast = 0
  elif ms < target * 0.8:
    inc q.fast
    q.slow = 0
  else:
    q.slow = 0
    q.fast = 0
  if q.slow >= 30:
    q.scale = max(0.7'f32, q.scale - 0.05'f32)
    q.slow = 0
  if q.fast >= 120:
    q.scale = min(1'f32, q.scale + 0.05'f32)
    q.fast = 0

func sampleCount*(w: FrameWindow): int = w.count
