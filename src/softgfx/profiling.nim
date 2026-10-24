## Warmup is based on submission frame IDs, not readback arrival order. Reports
## are rolling 120-sample windows, not frame latency/FPS or GPU+CPU summed time.
import std/math
import ./[quality, timing]

type
  TimingSummary* = object
    samples*: int
    medianMs*, p95Ms*: float32
  ProfileReport* = object
    frames*, warmupFrames*: int
    cpu*, gpu*: TimingSummary
  FrameProfile* = object
    frame, warmup: int
    cpu, gpu: FrameWindow

proc initFrameProfile*(warmupFrames = 30): FrameProfile =
  if warmupFrames < 0 or warmupFrames > 10000:
    raise newException(ValueError,"Invalid profiling warmup")
  result.warmup = warmupFrames

proc nextFrame*(p: var FrameProfile): int =
  if p.frame == high(int): raise newException(ValueError,"Reset profiler frame counter")
  inc p.frame
  p.frame

proc recordCpu*(p: var FrameProfile; frame: int; milliseconds: float64) =
  if frame > p.warmup and frame <= p.frame and milliseconds >= 0 and milliseconds <= 3.4028234663852886e38 and
      classify(milliseconds) notin {fcNan,fcInf,fcNegInf}:
    p.cpu.add(float32(milliseconds),allowZero=true)

proc recordGpu*(p: var FrameProfile; sample: GpuSample) =
  if sample.frame > p.warmup and sample.frame <= p.frame and sample.ms > 0 and sample.ms <= 3.4028234663852886e38 and
      classify(sample.ms) notin {fcNan,fcInf,fcNegInf}:
    p.gpu.add(float32(sample.ms))

proc resetGpu*(p: var FrameProfile) = p.gpu = default(FrameWindow)

proc report*(p: FrameProfile): ProfileReport =
  let cpu = p.cpu.percentiles()
  let gpu = p.gpu.percentiles()
  ProfileReport(frames:p.frame,warmupFrames:p.warmup,
    cpu:TimingSummary(samples:p.cpu.sampleCount,medianMs:cpu.median,p95Ms:cpu.p95),
    gpu:TimingSummary(samples:p.gpu.sampleCount,medianMs:gpu.median,p95Ms:gpu.p95))
