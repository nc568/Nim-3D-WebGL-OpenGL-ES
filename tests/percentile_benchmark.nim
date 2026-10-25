## Paired release observations: update + two reads, with alternating order.
import std/[algorithm, json]
import softgfx/quality
when defined(js):
  proc nowMs(): float64 {.importjs: "performance.now()".}
else:
  import std/[monotimes, times]
  proc nowMs(): float64 = float64(getMonoTime().ticks)/1_000_000

type ReferenceWindow = object
  values: array[120,float32]
  cursor: int
proc add(w: var ReferenceWindow; value: float32) =
  w.values[w.cursor] = value
  w.cursor = (w.cursor+1) mod 120
proc stats(w: ReferenceWindow): tuple[median,p95: float32] =
  var sorted = newSeq[float32](120)
  for i in 0..<120: sorted[i] = w.values[i]
  sorted.sort()
  (sorted[59],sorted[113])
proc valueAt(tick,pattern: int): float32 =
  case pattern
  of 0: 7'f32
  of 1: float32(tick mod 997+1)/4
  else: float32((tick*73+19) mod 211+1)/4
proc summary(values: seq[float64]): JsonNode =
  var sorted = values
  sorted.sort()
  %*{"medianMs":sorted[20],"p95Ms":sorted[38],"rawMs":values}
proc percentileBenchmark*(): string =
  const warmup = 20
  const samples = 41
  const frames = 1024
  var rows = newJArray()
  for pattern in 0..2:
    var optimized: FrameWindow
    var reference: ReferenceWindow
    for tick in 0..<120:
      optimized.add(valueAt(tick,pattern))
      reference.add(valueAt(tick,pattern))
    var fastTimes = newSeq[float64](samples)
    var oldTimes = newSeq[float64](samples)
    var checksum = 0.0
    for step in 0..<warmup+samples:
      var fastSum,oldSum: float64
      var fastMs,oldMs: float64
      for phase in 0..1:
        let fast = (step+phase) mod 2 == 0
        let started = nowMs()
        if fast:
          for i in 0..<frames:
            optimized.add(valueAt(120+step*frames+i,pattern))
            for read in 0..1:
              let s = optimized.percentiles()
              fastSum += float64(s.median)+float64(s.p95)
          fastMs = nowMs()-started
        else:
          for i in 0..<frames:
            reference.add(valueAt(120+step*frames+i,pattern))
            for read in 0..1:
              let s = reference.stats()
              oldSum += float64(s.median)+float64(s.p95)
          oldMs = nowMs()-started
      if fastSum != oldSum: raise newException(ValueError,"Percentile benchmark oracle mismatch")
      if step >= warmup:
        fastTimes[step-warmup] = fastMs
        oldTimes[step-warmup] = oldMs
        checksum += fastSum
    rows.add(%*{"pattern":pattern,"checksum":checksum,"ordered":summary(fastTimes),"sortReference":summary(oldTimes)})
  $(%*{"schemaVersion":1,"scope":"CPU update + two percentile reads per frame; not GPU/FPS; timings include runtime noise", "warmup":warmup,"samples":samples,"framesPerSample":frames,"readsPerFrame":2,"rows":rows})

when defined(js):
  proc publish(cb: proc(): cstring) {.importjs: "(globalThis.softgfxPercentileBench = #)".}
  proc browserBench(): cstring = cstring(percentileBenchmark())
  publish(browserBench)
else:
  echo "PERCENTILE_BENCH ",percentileBenchmark()
