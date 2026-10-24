import std/math
import softgfx/environment
var settings: SceneEffects
settings.validate()
settings.fogEnabled = true
for far in [0'f32,-1,Inf.float32,NaN.float32]:
  settings.fogFar = far
  var rejected = false
  try: settings.validate()
  except ValueError: rejected = true
  doAssert rejected
settings.fogFar = 100
settings.validate()
settings.blobCount = 1
settings.blobs[0] = BlobShadow(radiusX:1,radiusZ:2,strength:0.8)
settings.validate()
settings.blobs[0].strength = [0.8'f32][0]
settings.validate()
for bad in [0'f32,-1,100,Inf.float32,NaN.float32]:
  settings.blobs[0].radiusX = bad
  var rejected = false
  try: settings.validate()
  except ValueError: rejected = true
  doAssert rejected
let sky = skyMesh([0'f32,0,0],[1'f32,1,1])
doAssert sky.vertices.len == 4 and sky.indices.len == 6
echo "environment validation: PASS"
