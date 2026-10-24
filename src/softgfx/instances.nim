## Ground-oriented rigid transforms: Y rotation + translation + positive uniform scale.
## One record = 9 float32: position.xyz, cosYaw/sinYaw/scale, linear tint.rgb.
import std/math
import math3d

type
  InstanceMode* = enum fallbackDraws, coreInstancing, angleInstancing
  Instance* = object
    position*: Vec3
    yaw*, scale*: float32
    tint*: Vec3

const InstanceFloats* = 9
const InstanceBytes* = InstanceFloats * 4
const MaxInstances* = 65535 # Deliberate per-batch CPU/GPU allocation budget.

func instance*(position: Vec3 = [0'f32,0,0]; yaw = 0'f32;
               scale = 1'f32; tint: Vec3 = [1'f32,1,1]): Instance =
  Instance(position: position, yaw: yaw, scale: scale, tint: tint)

func finiteGpu(value: float32): bool =
  # Nim JS scalar float32 arithmetic may retain a double until the GL boundary.
  finite(value) and abs(float64(value)) <= 3.4028234663852886e38

proc validate*(items: openArray[Instance]; capacity: int) =
  if capacity < 1 or capacity > MaxInstances or items.len > capacity:
    raise newException(ValueError, "Instance count exceeds batch capacity")
  for i in 0..<items.len:
    if not finite(items[i].position) or not finiteGpu(items[i].yaw) or not finiteGpu(items[i].scale) or
        float64(items[i].scale) < 1.401298464324817e-45 or not finite(items[i].tint):
      raise newException(ValueError, "Non-finite or degenerate instance")
    for value in items[i].position:
      if not finiteGpu(value): raise newException(ValueError, "Instance position exceeds float32 range")
    for value in items[i].tint:
      if value < 0 or value > 1: raise newException(ValueError, "Tint must be linear RGB in [0,1]")

proc packInstances*(items: openArray[Instance]; data: var seq[float32]) =
  ## Validate the entire input before changing the previous snapshot.
  ## Indexed access avoids Nim JS temporary Instance objects/typed-array copies.
  items.validate(data.len div InstanceFloats)
  for i in 0..<items.len:
    let offset = i*InstanceFloats
    for axis in 0..2:
      data[offset+axis] = items[i].position[axis]
      data[offset+6+axis] = items[i].tint[axis]
    data[offset+3] = cos(items[i].yaw)
    data[offset+4] = sin(items[i].yaw)
    data[offset+5] = items[i].scale

proc packVisible*(items: openArray[Instance]; indices: openArray[int]; count: int;
                  data: var seq[float32]) =
  ## Index prefix from collectVisible. Validate everything before touching storage.
  items.validate(MaxInstances)
  if count < 0 or count > indices.len or count > data.len div InstanceFloats:
    raise newException(ValueError,"Visible count exceeds capacity")
  var previous = -1
  for i in 0..<count:
    if indices[i] <= previous or indices[i] >= items.len:
      raise newException(ValueError,"Visible indices must be increasing and in range")
    previous = indices[i]
  for i in 0..<count:
    let source = indices[i]
    let offset = i*InstanceFloats
    for axis in 0..2:
      data[offset+axis] = items[source].position[axis]
      data[offset+6+axis] = items[source].tint[axis]
    data[offset+3] = cos(items[source].yaw)
    data[offset+4] = sin(items[source].yaw)
    data[offset+5] = items[source].scale
