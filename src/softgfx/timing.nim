## Nonblocking bounded queue. Shared timer identity, explicit current context; do not
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
  GpuTimer* = ref object
    driver: TimerDriver
    alive, active: bool
    head, pending: int
    frames: array[TimerSlots,int]
    supported*: bool
    skipped*, invalidations*: int

proc bump(x: var int) =
  if x < high(int): inc x

proc destroyPool(driver: TimerDriver; count: int): bool =
  ## Each slot attempted once, even if another delete fails. No GL calls after loss.
  result = true
  for slot in 0..<count:
    try:
      if driver.lost(): return result
    except:
      return false # context state uncertain; do not issue more calls
    try: driver.destroy(slot)
    except: result = false

proc initGpuTimer*(driver: TimerDriver): GpuTimer =
  new(result)
  result.alive = true
  if not driver.supported: return
  if driver.create == nil or driver.destroy == nil or driver.beginQuery == nil or
      driver.endQuery == nil or driver.available == nil or driver.milliseconds == nil or
      driver.disjoint == nil or driver.lost == nil:
    raise newException(ValueError,"Incomplete timer driver")
  result.driver = driver
  var created = 0
  var complete = false
  try:
    for slot in 0..<TimerSlots:
      if not driver.create(slot): break
      inc created
    complete = created == TimerSlots
  except:
    discard destroyPool(driver,created) # preserve original create exception
    raise
  if not complete:
    if not destroyPool(driver,created):
      raise newException(ValueError,"Timer allocation rollback failed")
    return # CPU-only; rollback is OUTSIDE create's exception handler
  result.supported = true

proc abandon*(t: var GpuTimer) =
  ## Context lost/driver failure: no end/delete. All aliases become invalid.
  if t.isNil: return
  t.alive = false
  t.active = false
  t.supported = false
  t.head = 0
  t.pending = 0

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
  if t.isNil or not t.alive: raise newException(ValueError,"Timer is disposed/lost")
  if t.active: raise newException(ValueError,"Timer query already active")
  try:
    if not t.supported or not t.healthy(): return false
    if t.pending == TimerSlots:
      bump(t.skipped) # never wait, flush, finish or allocate another query
      return false
    let slot = (t.head+t.pending) mod TimerSlots
    t.frames[slot] = frame
    t.driver.beginQuery(slot)
    t.active = true
    return true
  except:
    t.abandon() # begin may have reached GL before throwing; no blind retry
    raise

proc endSample*(t: var GpuTimer) =
  if t.isNil or not t.active: return
  try:
    if t.driver.lost():
      t.abandon()
      return
    t.active = false # never retry a possibly completed end call
    t.driver.endQuery()
    inc t.pending
  except:
    t.abandon()
    raise

proc poll*(t: var GpuTimer; batch: var GpuBatch) =
  batch.count = 0
  if t.isNil: return
  if t.active: raise newException(ValueError,"Poll outside query scope")
  try:
    if not t.alive or not t.supported or not t.healthy(): return
    while t.pending > 0:
      if not t.driver.available(t.head): break
      let ms = t.driver.milliseconds(t.head) # ONLY after availability
      if classify(ms) notin {fcNan,fcInf,fcNegInf} and ms > 0:
        batch.samples[batch.count] = GpuSample(frame:t.frames[t.head],ms:ms)
        inc batch.count
      t.head = (t.head+1) mod TimerSlots
      dec t.pending
    if not t.healthy(): batch.count = 0
  except:
    batch.count = 0 # never expose a partial batch after failed retrieval
    t.abandon()
    raise

proc reset*(t: var GpuTimer) =
  ## Discard results without waiting; alias scopes share the same active query.
  if t.isNil: return
  t.endSample()
  if t.alive: t.invalidate()

proc dispose*(t: var GpuTimer) =
  if t.isNil or not t.alive: return
  t.alive = false # aliases cannot start new work during cleanup
  try:
    if t.supported:
      if t.driver.lost(): return
      t.endSample()
      if not t.supported: return # endSample observed context loss
      if not destroyPool(t.driver,TimerSlots):
        raise newException(ValueError,"Timer pool cleanup failed")
  finally:
    t.abandon()
