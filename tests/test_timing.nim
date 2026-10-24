import std/math
import softgfx/[timing, profiling, quality]

var ready: array[TimerSlots,bool]
var allocations, deletes, begins, ends, reads, lossCalls: int
var lost, disjoint: bool
var disjointOnRead = false
var driver: TimerDriver
driver.supported = true
driver.create = proc(slot: int): bool =
  inc allocations
  true
driver.destroy = proc(slot: int) = inc deletes
driver.beginQuery = proc(slot: int) =
  inc begins
  ready[slot] = false
driver.endQuery = proc() = inc ends
driver.available = proc(slot: int): bool = ready[slot]
driver.milliseconds = proc(slot: int): float64 =
  doAssert ready[slot], "Blocking query read"
  inc reads
  if disjointOnRead: disjoint = true
  5.25
driver.disjoint = proc(): bool = disjoint
driver.lost = proc(): bool =
  inc lossCalls
  lost
var timer = initGpuTimer(driver)
doAssert timer.supported and allocations == TimerSlots
var batch: GpuBatch
for frame in 1..TimerSlots:
  doAssert timer.beginSample(frame)
  timer.endSample()
doAssert not timer.beginSample(5) and timer.skipped == 1
timer.poll(batch)
doAssert batch.count == 0 and reads == 0
ready[1] = true # FIFO oldest unavailable: no speculative read
timer.poll(batch)
doAssert reads == 0
ready[0] = true
timer.poll(batch)
doAssert batch.count == 2 and batch.samples[0].frame == 1 and batch.samples[1].ms == 5.25
doAssert timer.beginSample(5)
var rejected = false
try: discard timer.beginSample(6)
except ValueError: rejected = true
doAssert rejected
rejected = false
try: timer.poll(batch)
except ValueError: rejected = true
doAssert rejected
timer.endSample()
disjoint = true
timer.poll(batch)
doAssert batch.count == 0 and timer.invalidations == 1
disjoint = false
doAssert timer.beginSample(6)
timer.endSample()
ready[0] = true
disjointOnRead = true
timer.poll(batch)
doAssert batch.count == 0 # discard even if disjoint appears during readback
disjointOnRead = false
disjoint = false
timer.reset()
doAssert timer.beginSample(7)
timer.endSample()
ready[0] = true
timer.poll(batch)
doAssert batch.count == 1 and batch.samples[0].frame == 7
timer.dispose()
timer.dispose()
doAssert deletes == TimerSlots and ends == begins
# Loss while active issues no end/delete GL calls.
timer = initGpuTimer(driver)
doAssert timer.beginSample(8)
let oldEnds = ends
let oldDeletes = deletes
lost = true
timer.endSample()
timer.dispose()
doAssert ends == oldEnds and deletes == oldDeletes
lost = false
# Loss may become observable between dispose's first check and endSample.
var lossChecks = 0
driver.lost = proc(): bool =
  inc lossChecks
  lossChecks >= 3
timer = initGpuTimer(driver)
doAssert timer.beginSample(10) # first check
let beforeLostDispose = deletes
timer.dispose() # second check false, third (endSample) true
doAssert deletes == beforeLostDispose
driver.lost = proc(): bool = lost
# Failed partial allocation is cleaned, unsupported path is a no-op.
driver.create = proc(slot: int): bool = slot < 2
let partialDeletes = deletes
timer = initGpuTimer(driver)
doAssert not timer.supported and deletes == partialDeletes+2
doAssert not timer.beginSample(1)
timer.dispose()
timer = initGpuTimer(TimerDriver())
doAssert not timer.beginSample(1)
timer.poll(batch)
doAssert batch.count == 0
timer.dispose()
# Warmup samples arriving late must remain excluded.
var profile = initFrameProfile(2)
for i in 1..5: doAssert profile.nextFrame() == i
for i in 1..5:
  profile.recordCpu(i,float64(i))
  profile.recordGpu(GpuSample(frame:i,ms:float64(i)*2))
doAssert profile.report.cpu.samples == 3 and profile.report.cpu.medianMs == 4
doAssert profile.report.gpu.samples == 3 and profile.report.gpu.p95Ms == 10
for value in [NaN,Inf,-1.0,1e100]:
  profile.recordCpu(5,value)
  profile.recordGpu(GpuSample(frame:5,ms:value))
doAssert profile.report.cpu.samples == 3 and profile.report.gpu.samples == 3
profile.resetGpu()
doAssert profile.report.gpu.samples == 0 and profile.report.cpu.samples == 3
profile.recordCpu(5,0)
profile.recordGpu(GpuSample(frame:5,ms:0))
doAssert profile.report.cpu.samples == 4 and profile.report.gpu.samples == 0
# Profiling must NOT censor real long frames (Quality's pause rule is separate).
profile.recordCpu(5,300)
profile.recordGpu(GpuSample(frame:5,ms:3000))
doAssert profile.report.cpu.p95Ms == 300 and profile.report.gpu.p95Ms == 3000
for i in 6..150:
  discard profile.nextFrame()
  profile.recordCpu(i,float64(i))
doAssert profile.report.cpu.samples == 120
# Frames 31..150; lower median = 90, nearest-rank p95 = 144.
doAssert profile.report.cpu.medianMs == 90 and profile.report.cpu.p95Ms == 144
echo "timer queue/disjoint/lifecycle/warmup/rolling statistics: PASS"

var reverseWindow: FrameWindow
for i in countdown(10,1): reverseWindow.add(float32(i))
doAssert reverseWindow.percentiles() == (5'f32,10'f32)
# Reject JS float32 scalars which still retain double precision until storage.
let huge = pow(10.0,100.0)
reverseWindow.add(float32(huge))
doAssert reverseWindow.sampleCount == 10

# Shared queue/scope and stale aliases; no duplicate end/delete callbacks.
driver.create = proc(slot: int): bool = true
timer = initGpuTimer(driver)
var alias = timer
doAssert alias.beginSample(100)
rejected = false
try: discard timer.beginSample(101)
except ValueError: rejected = true
doAssert rejected
let endBeforeAlias = ends
timer.endSample()
alias.endSample()
doAssert ends == endBeforeAlias+1
let deletedBeforeAlias = deletes
alias.dispose()
timer.dispose()
doAssert deletes == deletedBeforeAlias+TimerSlots and not timer.supported
rejected = false
try: discard timer.beginSample(102)
except ValueError: rejected = true
doAssert rejected
timer = initGpuTimer(driver)
rejected = false
try: discard alias.beginSample(103)
except ValueError: rejected = true
doAssert rejected
alias = timer
doAssert timer.beginSample(104)
let endsBeforeAbandon = ends
let deletesBeforeAbandon = deletes
alias.abandon()
timer.endSample()
timer.dispose()
doAssert ends == endsBeforeAbandon and deletes == deletesBeforeAbandon
var absent: GpuTimer
absent.endSample(); absent.reset(); absent.dispose(); absent.abandon()
batch.count = 2
absent.poll(batch)
doAssert batch.count == 0
rejected = false
try: discard absent.beginSample(1)
except ValueError: rejected = true
doAssert rejected

# Rollback delete failure must NOT re-enter cleanup and delete a slot twice.
var attempts: array[TimerSlots,int]
driver.create = proc(slot: int): bool = slot < 2
driver.destroy = proc(slot: int) =
  inc attempts[slot]
  if slot == 0: raise newException(ValueError,"injected delete")
rejected = false
try: timer = initGpuTimer(driver)
except ValueError: rejected = true
doAssert rejected and attempts == [1,1,0,0]
attempts = default(array[TimerSlots,int])
driver.create = proc(slot: int): bool =
  if slot == 2: raise newException(ValueError,"injected create")
  true
rejected = false
try: timer = initGpuTimer(driver)
except ValueError as e:
  rejected = e.msg == "injected create"
doAssert rejected and attempts == [1,1,0,0]
# Full disposal still attempts the remaining slots once after a delete failure.
attempts = default(array[TimerSlots,int])
driver.create = proc(slot: int): bool = true
timer = initGpuTimer(driver)
alias = timer
rejected = false
try: timer.dispose()
except ValueError: rejected = true
doAssert rejected and attempts == [1,1,1,1]
alias.dispose()
doAssert attempts == [1,1,1,1] and not alias.supported

# Callback failures invalidate all aliases; no speculative retry/partial batches.
driver.destroy = proc(slot: int) = inc deletes
let normalBegin = driver.beginQuery
let normalEnd = driver.endQuery
let normalRead = driver.milliseconds
for failure in 0..2:
  driver.beginQuery = normalBegin
  driver.endQuery = normalEnd
  driver.milliseconds = normalRead
  if failure == 0:
    driver.beginQuery = proc(slot: int) = raise newException(ValueError,"begin failed")
  elif failure == 1:
    driver.endQuery = proc() = raise newException(ValueError,"end failed")
  else:
    driver.milliseconds = proc(slot: int): float64 =
      if slot == 1: raise newException(ValueError,"read failed")
      3.0
  timer = initGpuTimer(driver)
  alias = timer
  rejected = false
  try:
    discard timer.beginSample(1)
    timer.endSample()
    if failure == 2:
      discard timer.beginSample(2)
      timer.endSample()
      ready[0] = true
      ready[1] = true
      timer.poll(batch)
  except ValueError: rejected = true
  doAssert rejected and not alias.supported
  if failure == 2: doAssert batch.count == 0
  let before = deletes
  alias.dispose()
  doAssert deletes == before # uncertain driver state: no more GL calls
  rejected = false
  try: discard alias.beginSample(3)
  except ValueError: rejected = true
  doAssert rejected
echo "Shared timer aliases / rollback exactly once / callback failure isolation PASS"

# Independent timer objects, one explicitly shared context guard.
proc fakeDriver(onBegin, onEnd: proc() {.closure.}): TimerDriver =
  result.supported = true
  result.create = proc(slot: int): bool = true
  result.destroy = proc(slot: int) = discard
  result.beginQuery = proc(slot: int) = onBegin()
  result.endQuery = onEnd
  result.available = proc(slot: int): bool = false
  result.milliseconds = proc(slot: int): float64 = 1
  result.disjoint = proc(): bool = false
  result.lost = proc(): bool = false
let scopes = newContextScopes()
var firstBegins, secondBegins, firstEnds, secondEnds: int
var first = initGpuTimer(fakeDriver(proc() = inc(firstBegins), proc() = inc(firstEnds)),scopes)
var second = initGpuTimer(fakeDriver(proc() = inc(secondBegins), proc() = inc(secondEnds)),scopes)
doAssert first.beginSample(1)
rejected = false
try: discard second.beginSample(2)
except ValueError: rejected = true
doAssert rejected and secondBegins == 0 and second.supported
rejected = false
try: second.poll(batch)
except ValueError: rejected = true
doAssert rejected and batch.count == 0
rejected = false
try: second.dispose()
except ValueError: rejected = true
doAssert rejected and second.supported
first.endSample()
doAssert second.beginSample(2)
second.endSample()
doAssert firstEnds == 1 and secondEnds == 1
# Frame and query are independent channels; measuring a frame is legal.
let frameOwner = newScopeOwner()
let foreignOwner = newScopeOwner()
scopes.claim(frameScope,frameOwner)
doAssert first.beginSample(3)
rejected = false
try: scopes.claim(frameScope,foreignOwner)
except ValueError: rejected = true
doAssert rejected
scopes.release(frameScope,foreignOwner) # must NOT unlock someone else's frame
rejected = false
try: scopes.claim(frameScope,foreignOwner)
except ValueError: rejected = true
doAssert rejected
first.endSample()
scopes.release(frameScope,frameOwner)
scopes.claim(frameScope,foreignOwner)
scopes.release(frameScope,foreignOwner)
first.dispose() # normal disposal does not invalidate the shared context
doAssert second.beginSample(4)
second.endSample()
second.dispose()
scopes.requireContext()
# Different context guards are independent; stale guards never reset in place.
let oldScopes = newContextScopes()
let newScopes = newContextScopes()
first = initGpuTimer(fakeDriver(proc() = inc(firstBegins), proc() = inc(firstEnds)),oldScopes)
second = initGpuTimer(fakeDriver(proc() = inc(secondBegins), proc() = inc(secondEnds)),newScopes)
doAssert first.beginSample(1) and second.beginSample(1)
let beforeInvalidEnd = firstEnds
oldScopes.invalidate()
rejected = false
try: first.endSample()
except ValueError: rejected = true
doAssert rejected and firstEnds == beforeInvalidEnd and not first.supported
second.endSample()
second.dispose()
newScopes.requireContext()
rejected = false
try: discard initGpuTimer(TimerDriver(),oldScopes)
except ValueError: rejected = true
doAssert rejected
# A failed begin poisons its shared context, not just that timer.
let faultScopes = newContextScopes()
var faulty = initGpuTimer(fakeDriver(proc() = raise newException(ValueError,"fault"),proc() = discard),faultScopes)
rejected = false
try: discard faulty.beginSample(1)
except ValueError: rejected = true
doAssert rejected
rejected = false
try: faultScopes.claim(frameScope,frameOwner)
except ValueError: rejected = true
doAssert rejected
echo "Shared context frame/query arbitration / rejection before driver / recovery isolation PASS"
