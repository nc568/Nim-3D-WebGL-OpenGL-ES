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
    template b: untyped = s.blobs[i]
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

type EffectChanges* = object
  parameters*, eye*, color*: bool
  blobs*: array[MaxBlobs,bool]

proc effectChanges*(previous, next: SceneEffects; changes: var EffectChanges;
                    force = false): bool =
  ## previous is the renderer's canonical GPU shadow; next must be validated.
  ## Inactive fields are zero, not arbitrary ignored caller data (possibly NaN).
  changes.parameters = force or previous.fogEnabled != next.fogEnabled or
    previous.blobCount != next.blobCount or
    (next.fogEnabled and (previous.fogNear != next.fogNear or previous.fogFar != next.fogFar))
  changes.eye = force
  changes.color = force
  for axis in 0..2:
    if previous.eye[axis] != (if next.fogEnabled: next.eye[axis] else: 0'f32): changes.eye = true
    if previous.fogColor[axis] != (if next.fogEnabled: next.fogColor[axis] else: 0'f32): changes.color = true
  result = changes.parameters or changes.eye or changes.color
  for i in 0..<MaxBlobs:
    template old: untyped = previous.blobs[i]
    template item: untyped = next.blobs[i]
    let active = i < next.blobCount
    changes.blobs[i] = force or old.radiusX != (if active: item.radiusX else: 0'f32) or
      old.radiusZ != (if active: item.radiusZ else: 0'f32) or
      old.yaw != (if active: item.yaw else: 0'f32) or
      old.strength != (if active: item.strength else: 0'f32)
    for axis in 0..2:
      if old.center[axis] != (if active: item.center[axis] else: 0'f32): changes.blobs[i] = true
    result = result or changes.blobs[i]

proc retainEffects*(source: SceneEffects; target: var SceneEffects) =
  ## Reuse nested JS arrays: no aggregate assignment / nimCopy in this hot path.
  target.fogEnabled = source.fogEnabled
  target.fogNear = if source.fogEnabled: source.fogNear else: 0'f32
  target.fogFar = if source.fogEnabled: source.fogFar else: 0'f32
  target.blobCount = source.blobCount
  for axis in 0..2:
    target.eye[axis] = if source.fogEnabled: source.eye[axis] else: 0'f32
    target.fogColor[axis] = if source.fogEnabled: source.fogColor[axis] else: 0'f32
  for i in 0..<MaxBlobs:
    let active = i < source.blobCount
    for axis in 0..2:
      target.blobs[i].center[axis] = if active: source.blobs[i].center[axis] else: 0'f32
    target.blobs[i].radiusX = if active: source.blobs[i].radiusX else: 0'f32
    target.blobs[i].radiusZ = if active: source.blobs[i].radiusZ else: 0'f32
    target.blobs[i].yaw = if active: source.blobs[i].yaw else: 0'f32
    target.blobs[i].strength = if active: source.blobs[i].strength else: 0'f32
