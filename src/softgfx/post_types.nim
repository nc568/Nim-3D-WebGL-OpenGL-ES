## Display-referred RGBA8 target. Lighting is linear in the scene shader, which
## encodes sRGB once. Post samples encoded RGB; grading explicitly decodes/encodes.
import std/math

type
  PostSettings* = object
    enabled*, fxaa*, dither*: bool
    scale*, exposure*, vignette*: float32
  SurfaceSize* = tuple[width, height: int]
  PipelineStats* = object
    renderWidth*, renderHeight*, outputWidth*, outputHeight*: int
    offscreen*: bool
    finalDrawCalls*, allocatedBytes*, targetRebuilds*: int

const DefaultTargetPixels* = 8*1024*1024

func defaultPost*(): PostSettings =
  PostSettings(enabled: true, fxaa: true, dither: true, scale: 1, exposure: 1)

proc validate*(s: PostSettings) =
  if classify(s.scale) in {fcNan,fcInf,fcNegInf} or
      classify(s.exposure) in {fcNan,fcInf,fcNegInf} or
      classify(s.vignette) in {fcNan,fcInf,fcNegInf}:
    raise newException(ValueError, "Non-finite post setting")
  # Include the float32 representations of 0.7/0.6: JS scalars can be doubles,
  # whereas values loaded from Float32Array have already been rounded.
  if float64(s.scale) < 0.699999988079071 or s.scale > 1 or s.exposure < 0.25 or s.exposure > 4 or
      s.vignette < 0 or float64(s.vignette) > 0.6000000238418579:
    raise newException(ValueError, "Post setting outside supported range")

proc scaledSize*(width,height: int; scale: float32): SurfaceSize =
  ## Quantize scale to 1/1000 then round pixels half-up with integer arithmetic.
  ## This avoids native float32 vs JS double discrepancies for e.g. 5 * 0.7.
  var s = defaultPost()
  s.scale = scale
  s.validate()
  if width < 0 or height < 0 or width > 16384 or height > 16384:
    raise newException(ValueError, "Surface dimensions must be 0..16384")
  if width == 0 or height == 0: return (0,0)
  let units = int(round(float64(scale)*1000))
  (max(1,(width*units+500) div 1000), max(1,(height*units+500) div 1000))

# Internal per-program uniform cache, shared by backend PostPass copies.
type PostUniformCache* = ref object
  valid*: bool
  width, height: int
  fxaa, dither: bool
  exposure, vignette: float32
  calls*, skips*: int

when defined(js):
  proc postFloat(value: float32): float32 {.importjs: "Math.fround(#)".}
else:
  func postFloat(value: float32): float32 = value

proc postUniformChanges*(c: PostUniformCache; w,h: int; s: PostSettings): int =
  ## Validated settings/dimensions only; bits: invSize/fxaa/dither/exposure/vignette.
  if not c.valid: return 31
  if c.width != w or c.height != h: result = result or 1
  if c.fxaa != s.fxaa: result = result or 2
  if c.dither != s.dither: result = result or 4
  if c.exposure != postFloat(s.exposure): result = result or 8
  if c.vignette != postFloat(s.vignette): result = result or 16

proc notePostUniform*(c: PostUniformCache) =
  if c.calls < high(int): inc c.calls

proc retainPostUniforms*(c: PostUniformCache; w,h: int; s: PostSettings; mask: int) =
  c.width = w; c.height = h
  c.fxaa = s.fxaa; c.dither = s.dither
  c.exposure = postFloat(s.exposure); c.vignette = postFloat(s.vignette)
  for bit in [1,2,4,8,16]:
    if (mask and bit) == 0 and c.skips < high(int): inc c.skips
  c.valid = true
