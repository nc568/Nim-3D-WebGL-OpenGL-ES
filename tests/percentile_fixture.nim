## Sort-based oracle remains test-only; exercises every ring wrap and duplicate.
import std/[algorithm, math]
import softgfx/quality

proc runPercentileProbe*() =
  for pattern in 0..3:
    var window: FrameWindow
    var history: seq[float32]
    doAssert window.percentiles() == (0'f32,0'f32)
    for tick in 0..<1024:
      let value = case pattern
        of 0: float32(tick mod 37)
        of 1: float32(1024-tick)
        of 2: 7'f32
        else: float32((tick*73+19) mod 211)/4
      window.add(value,allowZero=true)
      history.add(value)
      if history.len > 120: history.delete(0)
      var sorted = history
      sorted.sort()
      let expected = (sorted[(sorted.len-1) div 2],sorted[(sorted.len*95+99) div 100-1])
      doAssert window.sampleCount == history.len
      doAssert window.percentiles() == expected
      doAssert window.percentiles() == expected # nonmutating repeat reads
      for invalid in [NaN.float32,Inf.float32,NegInf.float32,-1'f32]:
        window.add(invalid,allowZero=true)
      window.add(0) # zero is rejected unless explicitly allowed
      doAssert window.sampleCount == history.len and window.percentiles() == expected
    # Value-copy isolation and resetting both ring and ordered state.
    var copy = window
    for i in 0..<120: copy.add(999)
    doAssert copy.percentiles() == (999'f32,999'f32)
    doAssert window.percentiles() != copy.percentiles()
    window = default(FrameWindow)
    doAssert window.sampleCount == 0 and window.percentiles() == (0'f32,0'f32)
    window.add(3)
    doAssert window.percentiles() == (3'f32,3'f32)
  echo "Rolling ordered window / 4096 sort oracles / duplicates / wrap / copy / reset PASS"
