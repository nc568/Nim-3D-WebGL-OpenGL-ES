import std/math
import softgfx, softgfx/geometry
import ../examples/scene

proc close(a,b: float32) = doAssert abs(a-b) < 0.0002
let id = identity()
doAssert id*id == id
let v = [2'f32,3,4,1]
doAssert id.transform(v) == v
let view = lookAt([0'f32,0,5], [0'f32,0,0], [0'f32,1,0])
doAssert view.transform([0'f32,0,5,1]) == [0'f32,0,0,1]
let projection = perspective(PI.float32/2, 2, 1, 11)
for depth in [1'f32,11]:
  let p = projection.transform([0'f32,0,-depth,1])
  close(p[2]/p[3], if depth==1: -1 else: 1)
close(projection[0]*2, projection[5])
let vp = projection*view
let p = vp.transform([1'f32,1,0,1])
let separate = projection.transform(view.transform([1'f32,1,0,1]))
for i in 0..3: close(p[i], separate[i])
for invalid in [0'f32,-1,NaN.float32,Inf.float32]:
  var rejected = false
  try: discard perspective(1,invalid,0.1,100)
  except ValueError: rejected = true
  doAssert rejected
var rejected = false
try: discard lookAt([0'f32,0,0],[0'f32,0,0],[0'f32,1,0])
except ValueError: rejected = true
doAssert rejected
rejected = false
try: discard lookAt([0'f32,1,0],[0'f32,0,0],[0'f32,1,0])
except ValueError: rejected = true
doAssert rejected
for yaw in [0'f32,0.5,1.7,3.14]:
  var mesh: MeshData
  mesh.addBox([1'f32,2,3], [2'f32,4,6], [0.5'f32,0.4,0.3], yaw)
  doAssert mesh.vertices.len == 36
  for i in countup(0,33,3):
    let a = mesh.vertices[i]
    let b = mesh.vertices[i+1]
    let c = mesh.vertices[i+2]
    close(dot(a.normal,a.normal),1)
    doAssert dot(cross(b.position-a.position,c.position-a.position),a.normal)>0
for baked in [false,true]:
  let mesh = arenaMesh(baked)
  mesh.validate()
  doAssert mesh.vertices.len == 864
  doAssert mesh.indices.len == 1296
for i in 0..200:
  let camera = arenaCamera(float32(i)*0.11, 7+float32(i mod 26))
  let center = camera.viewProjection(1.3).transform([0'f32,0.5,0,1])
  close(center[0]/center[3],0)
  close(center[1]/center[3],0)
  doAssert center[3]>0
echo "math3d + geometry: OK, matrix components=", vp.len
