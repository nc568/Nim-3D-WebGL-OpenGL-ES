import std/math
import softgfx, softgfx/geometry

var mesh: MeshData
mesh.addBox([0'f32,0,0],[1'f32,1,1],[1'f32,0,0])
let compact = mesh.indexed()
doAssert compact.vertices.len == 24 and compact.indices.len == 36
for i,index in compact.indices: doAssert compact.vertices[int(index)] == mesh.vertices[i]
compact.validate()
var invalid = compact
invalid.indices = @[0'u16,1,24]
var rejected = false
try: invalid.validate()
except ValueError: rejected = true
doAssert rejected
invalid = MeshData(vertices: @[Vertex(position: [NaN.float32,0,0]),Vertex(),Vertex()])
rejected = false
try: invalid.validate()
except ValueError: rejected = true
doAssert rejected
# 0xffff is reserved by WebGL2 fixed-index primitive restart.
let edge = MeshData(vertices: newSeq[Vertex](65535),indices: @[0'u16,1,65534])
edge.validate()
let tooLarge = MeshData(vertices: newSeq[Vertex](65536),indices: @[0'u16,1,65535])
rejected = false
try: tooLarge.validate()
except ValueError: rejected = true
doAssert rejected
let map = newOwnerMap(7,5)
map.applyDelta(2,1,3,3,@[1'u8,2,3,4,5,6,7,8,255])
let image = map.pixels
for y in 0..<5:
  for x in 0..<7:
    let inside = x>=2 and x<5 and y>=1 and y<4
    if not inside: doAssert image[y*7+x] == 0
    else: doAssert image[y*7+x] == (if x==4 and y==3: 255'u8 else: uint8((y-1)*3+x-1))
for rectangle in [[-1,0,1,1],[0,0,0,1],[6,4,2,1],[high(int),0,1,1],[0,0,7,5]]:
  rejected = false
  try: map.applyDelta(rectangle[0],rectangle[1],rectangle[2],rectangle[3],@[1'u8])
  except ValueError: rejected = true
  doAssert rejected and map.pixels == image
# Seeded monkey tests: compare the whole shadow to an independent reference.
var seed = 568'u32
var expected = image
for iteration in 0..<1000:
  seed = seed xor (seed shl 13)
  seed = seed xor (seed shr 17)
  seed = seed xor (seed shl 5)
  let x = int(seed mod 7)
  let y = int((seed shr 4) mod 5)
  let w = 1 + int((seed shr 8) mod uint32(7-x))
  let h = 1 + int((seed shr 16) mod uint32(5-y))
  var delta = newSeq[uint8](w*h)
  for i in 0..<delta.len: delta[i] = uint8((iteration+i) mod 256)
  map.applyDelta(x,y,w,h,delta)
  for row in 0..<h:
    for col in 0..<w: expected[(y+row)*7+x+col] = delta[row*w+col]
  doAssert map.pixels == expected
echo "indexed meshes + owner deltas: OK, cells=", map.pixels.len
