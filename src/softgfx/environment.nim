## Lightweight opaque-scene effects. Colors are LINEAR; defaults disable effects.
import ./[types, math3d]
const MaxBlobs* = 4

type
  BlobShadow* = object
    center*: Vec3                 # receiver-plane center, NOT caster height
    radiusX*, radiusZ*, yaw*, strength*: float32
  SceneEffects* = object
    fogEnabled*: bool
    eye*, fogColor*: Vec3
    fogNear*, fogFar*: float32
    blobCount*: int
    blobs*: array[MaxBlobs,BlobShadow]

proc validate*(s: SceneEffects) =
  if s.blobCount < 0 or s.blobCount > MaxBlobs:
    raise newException(ValueError,"Blob count outside fixed budget")
  if s.fogEnabled:
    if not finite(s.eye) or not finite(s.fogColor) or not finite(s.fogNear) or not finite(s.fogFar):
      raise newException(ValueError,"Non-finite fog setting")
    for i in 0..2:
      if abs(s.eye[i]) > 10000 or s.fogColor[i] < 0 or s.fogColor[i] > 1:
        raise newException(ValueError,"Fog eye/color outside supported range")
    if s.fogNear < 0 or s.fogFar > 1000 or s.fogFar-s.fogNear < 0.1:
      raise newException(ValueError,"Fog requires 0 <= near < far <= 1000, span >= .1")
  for i in 0..<s.blobCount:
    let b = s.blobs[i]
    if not finite(b.center) or not finite(b.radiusX) or not finite(b.radiusZ) or
        not finite(b.yaw) or not finite(b.strength):
      raise newException(ValueError,"Non-finite blob setting")
    for j in 0..2:
      if abs(b.center[j]) > 512: raise newException(ValueError,"Blob center exceeds small-world budget")
    if b.radiusX < 0.05 or b.radiusX > 64 or b.radiusZ < 0.05 or b.radiusZ > 64 or
        abs(b.yaw) > 10000 or b.strength < 0 or float64(b.strength) > 0.800000011920929:
      raise newException(ValueError,"Blob radius/yaw/strength outside supported range")

proc skyMesh*(bottom, top: Vec3): MeshData =
  ## Clip-space gradient, use an unlit renderer and renderBackground BEFORE scene.
  for color in [bottom,top]:
    for x in color:
      if not finite(x) or x < 0 or x > 1: raise newException(ValueError,"Invalid linear sky color")
  for i,pos in [[-1'f32,-1,0],[1'f32,-1,0],[1'f32,1,0],[-1'f32,1,0]]:
    result.vertices.add Vertex(position:pos,normal:[0'f32,1,0],color:(if i < 2: bottom else: top))
  result.indices = @[0'u16,1,2,0,2,3]
