## Render interpolation for MATCHED, same-order snapshots; not networking/physics.
## Inputs are validated completely before output mutation. Storage is caller-owned.
import std/math
import ./instances

func blend(a,b: float32; t: float64): float32 =
  # Double intermediates avoid (b-a) overflow for valid opposite float32 endpoints.
  # Clamp to the endpoint interval to preserve positive subnormal scale on JS.
  let lo = min(float64(a),float64(b))
  let hi = max(float64(a),float64(b))
  float32(clamp(float64(a)*(1-t)+float64(b)*t,lo,hi))

func blendYaw(a,b: float32; t: float64): float32 =
  let first = arctan2(sin(float64(a)),cos(float64(a)))
  let last = arctan2(sin(float64(b)),cos(float64(b)))
  var delta = last-first
  if delta >= PI: delta -= 2*PI
  if delta < -PI: delta += 2*PI
  # Antipodal orientation has no unique shortest arc. Choose negative rotation,
  # tolerating float32 vs JS scalar rounding around +/-pi.
  if abs(abs(delta)-PI) <= 1e-6: delta = -PI
  float32(first+delta*t)

proc interpolateInstances*(previous,current: openArray[Instance]; alpha: float64;
                           output: var seq[Instance]) =
  ## Clamp finite alpha to [0,1] (no extrapolation). Endpoints copied exactly.
  ## Same-index in-place output is supported; no resize or Instance construction.
  ## Entity identity/order MUST match. Reset history for teleports/spawn/despawn.
  if classify(alpha) in {fcNan,fcInf,fcNegInf}:
    raise newException(ValueError,"Non-finite interpolation alpha")
  if previous.len != current.len or output.len != current.len:
    raise newException(ValueError,"Interpolation requires matching snapshot lengths")
  previous.validate(MaxInstances)
  current.validate(MaxInstances)
  let t = clamp(alpha,0.0,1.0)
  for i in 0..<current.len:
    if t == 0 or t == 1:
      # Scalar copies preserve reusable JS object/typed-array storage.
      for axis in 0..2:
        output[i].position[axis] = if t == 0: previous[i].position[axis] else: current[i].position[axis]
        output[i].tint[axis] = if t == 0: previous[i].tint[axis] else: current[i].tint[axis]
      output[i].yaw = if t == 0: previous[i].yaw else: current[i].yaw
      output[i].scale = if t == 0: previous[i].scale else: current[i].scale
    else:
      for axis in 0..2:
        output[i].position[axis] = blend(previous[i].position[axis],current[i].position[axis],t)
        output[i].tint[axis] = blend(previous[i].tint[axis],current[i].tint[axis],t)
      output[i].yaw = blendYaw(previous[i].yaw,current[i].yaw,t)
      output[i].scale = blend(previous[i].scale,current[i].scale,t)

type
  StepPlan* = object
    steps*: int
    alpha*, droppedSeconds*: float64
    paused*: bool
  FixedClock* = object
    step, pauseThreshold, remainder: float64
    limit: int

proc initFixedClock*(stepSeconds = 1.0/60; maxSteps = 5;
                     pauseThresholdSeconds = 0.25): FixedClock =
  if classify(stepSeconds) in {fcNan,fcInf,fcNegInf} or
      classify(pauseThresholdSeconds) in {fcNan,fcInf,fcNegInf} or
      stepSeconds < 0.001 or stepSeconds > 1 or maxSteps < 1 or maxSteps > 32 or
      pauseThresholdSeconds < stepSeconds or pauseThresholdSeconds > 10:
    raise newException(ValueError,"Invalid fixed clock configuration")
  FixedClock(step:stepSeconds,limit:maxSteps,pauseThreshold:pauseThresholdSeconds)

func stepSeconds*(clock: FixedClock): float64 = clock.step

proc reset*(clock: var FixedClock) =
  ## Discard fractional time on suspend/resume; no simulation or pose mutation.
  clock.remainder = 0

proc advance*(clock: var FixedClock; elapsedSeconds: float64): StepPlan =
  ## Caller executes exactly steps fixed updates, then interpolates with alpha.
  ## Excess whole steps are DROPPED, not carried over indefinitely. No GL/clock IO.
  if clock.limit == 0: raise newException(ValueError,"Uninitialized fixed clock")
  if elapsedSeconds < 0 or classify(elapsedSeconds) in {fcNan,fcInf,fcNegInf}:
    raise newException(ValueError,"Invalid elapsed time")
  if elapsedSeconds > clock.pauseThreshold:
    result.paused = true
    result.droppedSeconds = elapsedSeconds+clock.remainder
    clock.remainder = 0
    return
  let total = clock.remainder+elapsedSeconds
  let whole = int(floor(total/clock.step+1e-9))
  result.steps = min(whole,clock.limit)
  result.droppedSeconds = float64(whole-result.steps)*clock.step
  clock.remainder = max(0.0,total-float64(whole)*clock.step)
  result.alpha = min(clock.remainder/clock.step,1.0-1e-12)
