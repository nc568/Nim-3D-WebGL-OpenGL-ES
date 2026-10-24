import std/[unittest, math]
import softgfx/post_types

suite "post settings and dimensions":
  test "rounding and quantization":
    check scaledSize(5,7,0.7) == (4,5)
    check scaledSize(640,480,0.8) == (512,384)
    check scaledSize(800,600,1) == (800,600)
    check scaledSize(1,1,0.7) == (1,1)
    check scaledSize(0,600,1) == (0,0)
  test "invalid settings and sizes":
    for value in [NaN.float32,Inf.float32,0.69'f32,1.01'f32]:
      expect ValueError: discard scaledSize(64,64,value)
    expect ValueError: discard scaledSize(-1,64,1)
    expect ValueError: discard scaledSize(16385,64,1)
    var s = defaultPost()
    s.exposure = 0
    expect ValueError: s.validate()
    s = defaultPost()
    s.vignette = 0.7
    expect ValueError: s.validate()

# Compiler regression: cproc has no GCC case-range syntax. Small ranges must
# expand to labels; large ones must take Nim's existing comparison-chain path.
proc rangeClass(x: int): int =
  case x
  of 1..5: 1
  of 100..100000: 2
  else: 3
for x in [0,1,5,6,99,100,100000,100001]:
  doAssert rangeClass(x) == (if x >= 1 and x <= 5: 1 elif x >= 100 and x <= 100000: 2 else: 3)
