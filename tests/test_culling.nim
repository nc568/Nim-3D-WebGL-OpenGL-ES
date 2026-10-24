import std/math
import softgfx, softgfx/[culling, geometry]
let f = frustum(identity())
let box = Bounds(lower:[-0.1,-0.2,-0.3],upper:[0.1,0.2,0.3])
doAssert f.visible(box)
for axis in 0..2:
  for sign in [-1.0,1.0]:
    var outside = box
    outside.lower[axis] = 2*sign-0.1
    outside.upper[axis] = 2*sign+0.1
    doAssert not f.visible(outside)
var touch = box
touch.lower[0] = 1
touch.upper[0] = 2
doAssert f.visible(touch)
let view = Camera(eye:[0'f32,0,0],target:[0'f32,0,-1],up:[0'f32,1,0],fovY:1,nearPlane:0.1,farPlane:20).viewProjection(1)
let camera = frustum(view)
doAssert camera.visible(box.transformedBounds(instance([0'f32,0,-2])))
doAssert not camera.visible(box.transformedBounds(instance([0'f32,0,2])))
doAssert not camera.visible(box.transformedBounds(instance([0'f32,0,-30])))
# Independent transformed-corner containment, 1000 rotations/scales/translations.
for i in 0..<1000:
  let pose = instance([float32(i mod 17),-2'f32,3],yaw=float32(i)*0.031,scale=0.1+float32(i mod 13))
  let world = box.transformedBounds(pose)
  for corner in 0..<8:
    let x = if (corner and 1) == 0: box.lower[0] else: box.upper[0]
    let y = if (corner and 2) == 0: box.lower[1] else: box.upper[1]
    let z = if (corner and 4) == 0: box.lower[2] else: box.upper[2]
    let c = cos(float64(pose.yaw))
    let s = sin(float64(pose.yaw))
    let point = [float64(pose.position[0])+float64(pose.scale)*(c*x+s*z),
      float64(pose.position[1])+float64(pose.scale)*y,
      float64(pose.position[2])+float64(pose.scale)*(-s*x+c*z)]
    for axis in 0..2: doAssert point[axis] >= world.lower[axis] and point[axis] <= world.upper[axis]
let poses = @[instance(),instance([4'f32,0,0]),instance([0.9'f32,0,0])]
var indices = newSeq[int](3)
let count = f.collectVisible(box,poses,indices)
doAssert count == 2 and indices[0] == 0 and indices[1] == 2
var packed = newSeq[float32](18)
packVisible(poses,indices,count,packed)
doAssert packed[9] == poses[2].position[0]
let old = packed
var rejected = false
try: packVisible(poses,[2,0],2,packed)
except ValueError: rejected = true
doAssert rejected and packed == old
rejected = false
try: discard frustum(default(Mat4))
except ValueError: rejected = true
doAssert rejected
var mesh: MeshData
mesh.addBox([0'f32,0,0],[2'f32,4,6],[1'f32,1,1])
doAssert mesh.meshBounds.lower == [-1.0,-2,-3]
echo "culling clip planes/corner containment/stable selection/packing: PASS"
# Homogeneous positive scaling must not change the clip volume.
for factor in [1e-20'f32,1e20'f32]:
  var scaled = identity()
  for i in 0..15: scaled[i] *= factor
  doAssert frustum(scaled).visible(box)
  doAssert not frustum(scaled).visible(Bounds(lower:[2.0,0,0],upper:[3.0,1,1]))
# Failed collection validates the complete snapshot before writing any output.
var invalidPoses = @[instance(),instance(scale=0)]
var output = @[77,88]
rejected = false
try: discard f.collectVisible(box,invalidPoses,output)
except ValueError: rejected = true
doAssert rejected and output == @[77,88]
doAssert f.collectVisible(box,newSeq[Instance](),output) == 0
rejected = false
try: packVisible(poses,[0,99],2,packed)
except ValueError: rejected = true
doAssert rejected and packed == old
