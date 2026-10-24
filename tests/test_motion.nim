import std/math
import softgfx/[motion, instances]

let before = @[instance([-2'f32,0,2],yaw=350'f32*PI.float32/180,scale=0.5,tint=[0'f32,0.2,1])]
let after = @[instance([2'f32,2,-2],yaw=10'f32*PI.float32/180,scale=1.5,tint=[1'f32,0.8,0])]
var output = newSeq[Instance](1)
interpolateInstances(before,after,0.5,output)
doAssert output[0].position == [0'f32,1,0] and output[0].scale == 1
for x in output[0].tint: doAssert abs(x-0.5) < 1e-6
doAssert abs(sin(output[0].yaw)) < 1e-6 and cos(output[0].yaw) > 0.999
for alpha in [-10.0,0.0,1.0,10.0]:
  interpolateInstances(before,after,alpha,output)
  doAssert output[0] == (if alpha <= 0: before[0] else: after[0])
for endYaw in [PI.float32,-PI.float32]:
  interpolateInstances(@[instance()],@[instance(yaw=endYaw)],0.5,output)
  doAssert abs(float64(output[0].yaw)+PI/2) < 1e-6
# In-place same-index output, and atomic rejection of the entire snapshot.
var inplace = @[before[0]]
interpolateInstances(inplace,after,0.5,inplace)
interpolateInstances(before,after,0.5,output)
doAssert inplace == output
let saved = output
for bad in [NaN,Inf,NegInf]:
  var rejected = false
  try: interpolateInstances(before,after,bad,output)
  except ValueError: rejected = true
  doAssert rejected and output == saved
var rejected = false
try: interpolateInstances(before,@[instance(scale=0)],0.5,output)
except ValueError: rejected = true
doAssert rejected and output == saved
rejected = false
try: interpolateInstances(before,newSeq[Instance](),0.5,output)
except ValueError: rejected = true
doAssert rejected and output == saved
# Float32 endpoint extremes must not overflow via a naive (b-a) lerp.
let big = 3.0e38'f32
# Pinned Nim JS prints a min-subnormal f32 literal as 1e-45 (a double).
# Exercise the exact GPU value rather than that codegen decimal approximation.
let tiny = float32(pow(2.0,-149.0))
interpolateInstances(@[instance([-big,0,0],scale=tiny)],
  @[instance([big,0,0],scale=tiny)],0.3,output)
validate(output,1)
doAssert abs(float64(output[0].position[0])/float64(big)+0.4) < 1e-6
var empty: seq[Instance]
interpolateInstances(empty,empty,0.5,empty)

var clock = initFixedClock(0.05,3)
let first = clock.advance(0.02)
doAssert first.steps == 0 and abs(first.alpha-0.4) < 1e-9
let next = clock.advance(0.03)
doAssert next.steps == 1 and next.alpha < 1e-8
let saturated = clock.advance(0.225)
doAssert saturated.steps == 3 and abs(saturated.alpha-0.5) < 1e-8
doAssert abs(saturated.droppedSeconds-0.05) < 1e-8
let pause = clock.advance(10)
doAssert pause.paused and pause.steps == 0 and pause.alpha == 0
doAssert abs(pause.droppedSeconds-10.025) < 1e-8
discard clock.advance(0.02)
for bad in [-1.0,NaN,Inf]:
  rejected = false
  try: discard clock.advance(bad)
  except ValueError: rejected = true
  doAssert rejected and abs(clock.advance(0).alpha-0.4) < 1e-9
clock.reset()
doAssert clock.advance(0).alpha == 0
# Equal elapsed time, independent regular RAF partitions.
for hz in [30,60,120,144]:
  clock = initFixedClock(0.05,5)
  var total = 0
  for i in 1..hz*10:
    let plan = clock.advance(1.0/float64(hz))
    total += plan.steps
    doAssert plan.alpha >= 0 and plan.alpha < 1 and plan.droppedSeconds == 0
  doAssert total == 200
rejected = false
var unset: FixedClock
try: discard unset.advance(0)
except ValueError: rejected = true
doAssert rejected
for step in [0.0,NaN,Inf,2.0]:
  rejected = false
  try: discard initFixedClock(step)
  except ValueError: rejected = true
  doAssert rejected
echo "motion shortest-arc/linear-color/endpoints/atomicity/fixed-clock: PASS"

# Same-index current-buffer alias is safe too.
var inCurrent = @[after[0]]
interpolateInstances(before,inCurrent,0.5,inCurrent)
interpolateInstances(before,after,0.5,output)
doAssert inCurrent == output
# Validate later invalid records before writing even the first valid result.
var twoOutputs = @[instance([99'f32,98,97]),instance()]
rejected = false
try:
  interpolateInstances(@[before[0],before[0]],@[after[0],instance(scale=0)],0.5,twoOutputs)
except ValueError: rejected = true
doAssert rejected and twoOutputs[0].position == [99'f32,98,97]
# Independent midpoint oracle: normalize the sum of endpoint unit vectors.
for i in 1..1000:
  let a = float32(i)*0.071'f32
  let b = -float32(i)*0.113'f32
  let x = cos(float64(a))+cos(float64(b))
  let y = sin(float64(a))+sin(float64(b))
  let length = sqrt(x*x+y*y)
  if length > 1e-5:
    interpolateInstances(@[instance(yaw=a)],@[instance(yaw=b)],0.5,output)
    doAssert abs(cos(float64(output[0].yaw))-x/length) < 1e-6
    doAssert abs(sin(float64(output[0].yaw))-y/length) < 1e-6
