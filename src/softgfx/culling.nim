## Conservative GL clip-volume culling; no GL calls, occlusion or sorting.
## Bounds use float64 CPU arithmetic and outward padding for GPU float32 rounding.
import std/math
import ./[types, math3d, instances]

type
  Bounds* = object
    lower*, upper*: array[3,float64]
  Frustum* = object
    planes: array[6,array[4,float64]]
    ready: bool

proc validate*(b: Bounds) =
  for i in 0..2:
    if classify(b.lower[i]) in {fcNan,fcInf,fcNegInf} or
        classify(b.upper[i]) in {fcNan,fcInf,fcNegInf} or
        abs(b.lower[i]) > 1e100 or abs(b.upper[i]) > 1e100 or b.lower[i] > b.upper[i]:
      raise newException(ValueError,"Invalid finite bounds")

proc validateLocal(b: Bounds) =
  b.validate()
  for axis in 0..2:
    if abs(b.lower[axis]) > 3.4028234663852886e38 or abs(b.upper[axis]) > 3.4028234663852886e38:
      raise newException(ValueError,"Local bounds exceed GPU float32 range")

proc meshBounds*(mesh: MeshData): Bounds =
  mesh.validate()
  for axis in 0..2:
    result.lower[axis] = float64(mesh.vertices[0].position[axis])
    result.upper[axis] = result.lower[axis]
  for v in mesh.vertices:
    for axis in 0..2:
      result.lower[axis] = min(result.lower[axis],float64(v.position[axis]))
      result.upper[axis] = max(result.upper[axis],float64(v.position[axis]))

proc frustum*(matrix: Mat4): Frustum =
  var maximum = 0.0
  for value in matrix:
    if not finite(value) or abs(float64(value)) > 3.4028234663852886e38:
      raise newException(ValueError,"Invalid frustum matrix")
    maximum = max(maximum,abs(float64(value)))
  if maximum == 0: raise newException(ValueError,"Zero frustum matrix")
  # GL homogeneous clip tests: row3 +/- row0/1/2; depth is [-w,+w].
  for axis in 0..2:
    for side in 0..1:
      for col in 0..3:
        result.planes[axis*2+side][col] =
          (float64(matrix[col*4+3])+(if side == 0: 1.0 else: -1.0)*float64(matrix[col*4+axis]))/maximum
  result.ready = true

proc intersects(f: Frustum; b: Bounds): bool =
  for row in 0..5:
    var distance = f.planes[row][3]
    var magnitude = abs(distance)
    for axis in 0..2:
      let coordinate = if f.planes[row][axis] >= 0: b.upper[axis] else: b.lower[axis]
      let term = f.planes[row][axis]*coordinate
      distance += term
      magnitude += abs(term)
    if distance < -1e-5*(1+magnitude): return false
  true

proc visible*(f: Frustum; b: Bounds): bool =
  if not f.ready: raise newException(ValueError,"Uninitialized frustum")
  b.validate()
  f.intersects(b)

proc transformedInto(local: Bounds; item: Instance; output: var Bounds) =
  let c = cos(float64(item.yaw))
  let s = sin(float64(item.yaw))
  let scale = float64(item.scale)
  for axis in 0..2:
    let a = if axis == 0: c elif axis == 2: -s else: 0.0
    let b = if axis == 0: s elif axis == 2: c else: 0.0
    var lo,hi,magnitude: float64
    if axis == 1:
      lo = local.lower[1]*scale
      hi = local.upper[1]*scale
      magnitude = max(abs(lo),abs(hi))
    else:
      lo = (min(a*local.lower[0],a*local.upper[0])+min(b*local.lower[2],b*local.upper[2]))*scale
      hi = (max(a*local.lower[0],a*local.upper[0])+max(b*local.lower[2],b*local.upper[2]))*scale
      magnitude = (abs(a)*max(abs(local.lower[0]),abs(local.upper[0]))+
        abs(b)*max(abs(local.lower[2]),abs(local.upper[2])))*scale
    let translation = float64(item.position[axis])
    let padding = 1e-5*(1+abs(translation)+magnitude)
    output.lower[axis] = translation+lo-padding
    output.upper[axis] = translation+hi+padding

proc transformedBounds*(local: Bounds; item: Instance): Bounds =
  local.validateLocal()
  validate([item],1)
  local.transformedInto(item,result)

proc collectVisible*(f: Frustum; local: Bounds; items: openArray[Instance];
                     indices: var seq[int]): int =
  ## Caller reserves indices.len >= items.len once. Only [0..<result] is valid;
  ## order is preserved. No output resize; invalid input leaves output unchanged.
  if not f.ready: raise newException(ValueError,"Uninitialized frustum")
  local.validateLocal()
  items.validate(MaxInstances)
  if indices.len < items.len: raise newException(ValueError,"Visibility buffer too small")
  var world: Bounds # one scratch box per collection, not per instance
  for i in 0..<items.len:
    local.transformedInto(items[i],world)
    if f.intersects(world):
      indices[result] = i
      inc result
