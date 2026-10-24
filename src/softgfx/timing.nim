## Nonblocking, bounded GPU query queue. Single owner/current context; do not
## interleave elapsed queries from other profilers. No clock or GL enums here.
import std/math
const TimerSlots* = 4

type
  TimerDriver* = object
    supported*: bool
    create*: proc(slot: int): bool {.closure.}
    destroy*, beginQuery*: proc(slot: int) {.closure.}
    endQuery*: proc() {.closure.}
    available*: proc(slot: int): bool {.closure.}
    milliseconds*: proc(slot: int): float64 {.closure.}
    disjoint*, lost*: proc(): bool {.closure.}
  GpuSample* = object
    frame*: int
    ms*: float64
  GpuBatch* = object
    count*: int
    samples*: array[TimerSlots,GpuSample]
  GpuTimer* = object
    driver: TimerDriver
    alive, active: bool
    head, pending: int
    frames: array[TimerSlots,int]
    supported*: bool
    skipped*, invalidations*: int

proc bump(x: var int) =
  if x < high(int): inc x

proc initGpuTimer*(driver: TimerDriver): GpuTimer =
  result.alive = true
  if not driver.supported: return
  if driver.create == nil or driver.destroy == nil or driver.beginQuery == nil or
      driver.endQuery == nil or driver.available == nil or driver.milliseconds == nil or
      driver.disjoint == nil or driver.lost == nil:
    raise newException(ValueError,"Incomplete timer driver")
  result.driver = driver
  var created = 0
  try:
    for slot in 0..<TimerSlots:
      if not driver.create(slot):
        for old in 0..<created: driver.destroy(old)
        return # allocation unavailable: CPU-only, no partial query pool
      inc created
  except:
    for old in 0..<created: driver.destroy(old)
    raise
  result.supported = true

proc abandon*(t: var GpuTimer) =
  ## Context lost: NEVER issue end/delete calls on invalid handles.
  t = default(GpuTimer)

proc invalidate(t: var GpuTimer) =
  t.head = 0
  t.pending = 0
  bump(t.invalidations)

proc healthy(t: var GpuTimer): bool =
  if t.driver.lost():
    t.abandon()
    return false
  if t.driver.disjoint():
    t.invalidate()
    return false
  true

proc beginSample*(t: var GpuTimer; frame: int): bool =
  if not t.alive: raise newException(ValueError,"Timer is disposed/lost")
  if t.active: raise newException(ValueError,"Timer query already active")
  if not t.supported or not t.healthy(): return false
  if t.pending == TimerSlots:
    bump(t.skipped) # never wait, flush, finish or allocate another query
    return false
  let slot = (t.head+t.pending) mod TimerSlots
  t.frames[slot] = frame
  t.driver.beginQuery(slot)
  t.active = true
  true

proc endSample*(t: var GpuTimer) =
  if not t.active: return
  if t.driver.lost():
    t.abandon()
    return
  t.driver.endQuery()
  t.active = false
  inc t.pending

proc poll*(t: var GpuTimer; batch: var GpuBatch) =
  batch.count = 0
  if t.active: raise newException(ValueError,"Poll outside query scope")
  if not t.alive or not t.supported or not t.healthy(): return
  while t.pending > 0:
    if not t.driver.available(t.head): break
    let ms = t.driver.milliseconds(t.head) # ONLY after availability
    if classify(ms) notin {fcNan,fcInf,fcNegInf} and ms > 0:
      batch.samples[batch.count] = GpuSample(frame:t.frames[t.head],ms:ms)
      inc batch.count
    t.head = (t.head+1) mod TimerSlots
    dec t.pending
  # A disjoint discovered while retrieving invalidates the ENTIRE batch.
  if not t.healthy(): batch.count = 0

proc reset*(t: var GpuTimer) =
  ## Configuration/visibility change. Results in flight are discarded, not waited
  ## for. GL permits reusing query objects; begin resets result availability.
  t.endSample()
  if t.alive: t.invalidate()

proc dispose*(t: var GpuTimer) =
  if not t.alive: return
  if t.supported:
    if t.driver.lost():
      t.abandon()
      return
    t.endSample()
    if not t.alive: return # loss may have been observed by endSample
    for slot in 0..<TimerSlots: t.driver.destroy(slot)
  t = default(GpuTimer)
