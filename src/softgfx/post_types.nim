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
