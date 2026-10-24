## Conservative, opt-in GPU-only controller. Not a frame-time/FPS estimator.
## Samples need matching submission timestamps; no CPU fallback is permitted.
import std/math
import ./[quality, timing, post_types]

const StampSlots = 64

type
  AutoScale* = object
    units, current, warmupThrough, lastAccepted: int
    stamps: array[StampSlots,tuple[frame: int, ms: float64]]
    lastSubmit, cooldownUntil, firstMs: float64
    firstFrame, slowWindows, fastWindows: int
    samples: FrameWindow
    changes*: int

proc initAutoScale*(scale = 1'f32): AutoScale =
  discard scaledSize(1,1,scale) # common finite/range validation
  result.units = int(round(float64(scale)*1000))
  result.warmupThrough = 30

func scale*(q: AutoScale): float32 = float32(q.units)/1000

proc clearEvidence(q: var AutoScale) =
  q.samples = default(FrameWindow)
  q.slowWindows = 0
  q.fastWindows = 0

proc reset*(q: var AutoScale; scale: float32; settling = false) =
  let cooldown = q.cooldownUntil
  let changes = q.changes
  q = initAutoScale(scale)
  q.changes = changes
  if settling:
    q.warmupThrough = 60
    q.cooldownUntil = cooldown

proc submitted*(q: var AutoScale; frame: int; nowMs: float64) =
  if q.units < 700 or q.units > 1000 or frame <= q.current or frame > high(int)-60 or nowMs < 0 or
      classify(nowMs) in {fcNan,fcInf,fcNegInf} or nowMs < q.lastSubmit:
    raise newException(ValueError,"Invalid autoscale submission clock/frame")
  if q.current > 0 and nowMs-q.lastSubmit > 250:
    q.clearEvidence()
    q.warmupThrough = frame+30
  q.current = frame
  q.lastSubmit = nowMs
  q.stamps[frame mod StampSlots] = (frame,nowMs)

proc observe*(q: var AutoScale; sample: GpuSample; nowMs: float64;
              targetMs = 16.667): bool =
  ## 12 fresh samples/window, 3 slow windows down, 10 fast windows up.
  ## Window span <=32 submissions and <=600ms; readback age <=8 frames/200ms.
  if targetMs <= 0 or classify(targetMs) in {fcNan,fcInf,fcNegInf} or
      nowMs < q.lastSubmit or classify(nowMs) in {fcNan,fcInf,fcNegInf}:
    q.clearEvidence()
    return false
  if sample.frame <= q.lastAccepted: return false # duplicate/out-of-order
  if sample.frame <= 0 or sample.frame > q.current:
    q.clearEvidence()
    return false
  let stamp = q.stamps[sample.frame mod StampSlots]
  if stamp.frame != sample.frame or q.current-sample.frame > 8 or
      nowMs-stamp.ms > 200 or sample.ms <= 0 or sample.ms > 250 or
      classify(sample.ms) in {fcNan,fcInf,fcNegInf}:
    q.clearEvidence()
    return false
  if sample.frame <= q.warmupThrough or nowMs < q.cooldownUntil: return false
  if q.lastAccepted > 0 and sample.frame-q.lastAccepted > 8: q.clearEvidence()
  q.lastAccepted = sample.frame
  if q.samples.sampleCount > 0 and
      (sample.frame-q.firstFrame > 32 or nowMs-q.firstMs > 600): q.clearEvidence()
  if q.samples.sampleCount == 0:
    q.firstFrame = sample.frame
    q.firstMs = nowMs
  q.samples.add(float32(sample.ms))
  if q.samples.sampleCount < 12: return false
  let stats = q.samples.percentiles()
  q.samples = default(FrameWindow)
  if stats.median > targetMs*1.1:
    inc q.slowWindows
    q.fastWindows = 0
  elif stats.p95 < targetMs*0.8:
    inc q.fastWindows
    q.slowWindows = 0
  else:
    q.clearEvidence()
  var next = q.units
  if q.slowWindows >= 3: next = max(700,q.units-50)
  if q.fastWindows >= 10: next = min(1000,q.units+50)
  if q.slowWindows >= 3 or q.fastWindows >= 10: q.clearEvidence()
  if next == q.units: return false
  q.units = next
  if q.changes < high(int): inc q.changes
  q.warmupThrough = q.current+60
  q.cooldownUntil = nowMs+1000
  true
