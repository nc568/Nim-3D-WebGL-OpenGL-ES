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

suite "post uniform cache":
  test "field masks, canonical equality, explicit invalidation":
    var c: PostUniformCache
    new(c)
    var s = defaultPost()
    check postUniformChanges(c,64,64,s) == 31
    retainPostUniforms(c,64,64,s,31)
    check postUniformChanges(c,64,64,s) == 0
    s.scale = 0.8; s.enabled = false # not uniforms
    check postUniformChanges(c,64,64,s) == 0
    check postUniformChanges(c,63,64,s) == 1
    s.fxaa = false
    check postUniformChanges(c,64,64,s) == 2
    s.dither = false
    check postUniformChanges(c,64,64,s) == 6
    s.exposure = 0.5; s.vignette = 0.2
    check postUniformChanges(c,63,64,s) == 31
    retainPostUniforms(c,63,64,s,31)
    s.exposure += float32(pow(10.0,-10.0))
    check postUniformChanges(c,63,64,s) == 0
    c.valid = false
    check postUniformChanges(c,63,64,s) == 31
    c.calls = high(int); c.skips = high(int)
    notePostUniform(c); retainPostUniforms(c,63,64,s,0)
    check c.calls == high(int) and c.skips == high(int)
