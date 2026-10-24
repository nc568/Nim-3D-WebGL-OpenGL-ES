import std/math
import softgfx

var data = newSeq[float32](3*InstanceFloats)
let items = @[instance([2'f32,3,4],PI.float32/2,2,[0.2'f32,0.4,0.8]), instance()]
packInstances(items,data)
doAssert data[0..2] == @[2'f32,3,4]
doAssert abs(data[3]) < 0.000001 and abs(data[4]-1) < 0.000001
# Uniform scale is independent of rotation; color occupies its own slot.
doAssert data[5] == 2
for i in 0..2: doAssert abs(data[6+i]-items[0].tint[i]) < 0.0000001
doAssert data[9..17] == @[0'f32,0,0,1,0,1,1,1,1]
let original = data
for bad in [instance(scale=0),instance(scale= -1),instance(yaw=NaN.float32),
            instance([Inf.float32,0,0]),instance(tint=[1.1'f32,0,0])]:
  var rejected = false
  try: packInstances(@[instance(),bad],data)
  except ValueError: rejected = true
  doAssert rejected and data == original
var rejected = false
try: packInstances(newSeq[Instance](4),data)
except ValueError: rejected = true
doAssert rejected and data == original
packInstances(newSeq[Instance](),data)
doAssert data == original
# Independent scalar transform check: +90deg maps local +X toward world -Z.
let transformed: Vec3 = [data[0]+data[3]*data[5],data[1],data[2]-data[4]*data[5]]
doAssert abs(transformed[0]-2)<0.000001 and abs(transformed[2]-2)<0.000001
for i in 0..<1000:
  let angle = float32(i)*0.027'f32
  packInstances(@[instance(yaw=angle)],data)
  doAssert abs(data[3]*data[3]+data[4]*data[4]-1) < 0.00001
# JS evaluates float32 arithmetic as double: reject overflow/underflow before GL conversion.
var exponent = 100'f32
for scale in [pow(10'f32,exponent),pow(10'f32,-exponent)]:
  rejected = false
  try: packInstances(@[instance(scale=scale)],data)
  except ValueError: rejected = true
  doAssert rejected
# No GL access for impossible capacities.
rejected = false
try: discard initRenderer(default(Context),baseline(gles2),MeshData(vertices: newSeq[Vertex](3)),instanceCapacity=MaxInstances+1)
except ValueError: rejected = true
doAssert rejected
echo "instance packing/validation: OK"
