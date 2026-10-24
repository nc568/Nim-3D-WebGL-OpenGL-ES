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
