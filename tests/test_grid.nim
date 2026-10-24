import std/math
import softgfx/[culling, instances, math3d]
let local = Bounds(lower:[-0.2,-0.3,-0.4],upper:[0.2,0.3,0.4])
let region = Bounds(lower:[-32.0,-2.0,-32.0],upper:[32.0,2.0,32.0])
var grid = initSpatialGrid(region,[16,1,16],1024)
var poses = newSeq[Instance](1024)
var flat, indexed: seq[int]
flat.setLen(1024); indexed.setLen(1024)
var stats: GridQueryStats
for i in 0..<1024:
  poses[i] = instance([float32(i mod 32)*2-31,0,float32(i div 32)*2-31])
grid.rebuild(local,poses)
let f = frustum(identity())
let n = f.collectVisible(local,poses,flat)
doAssert f.collectVisible(grid,indexed,stats) == n
for i in 0..<n: doAssert indexed[i] == flat[i]
doAssert stats.instanceTests < poses.len div 4
let savedTests = stats.instanceTests
# Many poses/cameras, out-of-region centers, giant boxes and conservative edges.
for tick in 0..<40:
  for i in 0..<poses.len:
    poses[i] = instance([float32(sin(float64(i+tick))*70),float32(i mod 7)-3,
      float32(cos(float64(i*3+tick))*70)],yaw=float32(i)*0.1,
      scale=(if i mod 61 == 0: 30'f32 else: 0.2'f32+float32(i mod 5)))
  grid.rebuild(local,poses)
  let camera = Camera(eye:[float32(tick)-20,10,40],target:[0'f32,0,0],
    up:[0'f32,1,0],fovY:0.8,nearPlane:0.1,farPlane:150)
  let view = frustum(camera.viewProjection(1.3))
  let count = view.collectVisible(local,poses,flat)
  doAssert view.collectVisible(grid,indexed,stats) == count
  for i in 0..<count: doAssert indexed[i] == flat[i]
# Invalid rebuild leaves previous cache queryable.
let prior = f.collectVisible(grid,indexed,stats)
let snapshot = indexed
poses[1023].scale = 0
var rejected = false
try: grid.rebuild(local,poses)
except ValueError: rejected = true
doAssert rejected and f.collectVisible(grid,indexed,stats) == prior
doAssert indexed == snapshot
var tooSmall: seq[int]
let savedStats = stats
rejected = false
try: discard f.collectVisible(grid,tooSmall,stats)
except ValueError: rejected = true
doAssert rejected and stats == savedStats
grid.rebuild(local,[])
doAssert f.collectVisible(grid,indexed,stats) == 0 and stats.instanceTests == 0
var fresh = initSpatialGrid(region,[1,1,1],1)
rejected = false
try: discard f.collectVisible(fresh,indexed,stats)
except ValueError: rejected = true
doAssert rejected
fresh.rebuild(local,[instance([1.2'f32,0,0])])
doAssert f.collectVisible(fresh,indexed,stats) == 1 # touching clip edge
for bad in [[0,1,1],[33,1,1]]:
  rejected = false
  try: discard initSpatialGrid(region,bad,1)
  except ValueError: rejected = true
  doAssert rejected
echo "Grid flat-oracle/atomicity/empty/outliers PASS; sparse instance tests: ",savedTests," / 1024"
# Ordering threshold transitions and nontrivial unsorted sparse prefixes.
for hits in [0,1,2,3,4,7,8,16,32,64,128,256,768,1024]:
  for i in 0..<poses.len:
    if (i*137) mod 1024 < hits:
      poses[i] = instance([float32((i*31) mod 17)/20'f32-0.4'f32,0,
        float32((i*19) mod 17)/20'f32-0.4'f32])
    else: poses[i] = instance([50'f32,50,50])
    indexed[i] = -7
  grid.rebuild(local,poses)
  doAssert f.collectVisible(local,poses,flat) == hits
  doAssert f.collectVisible(grid,indexed,stats) == hits
  for i in 0..<hits: doAssert indexed[i] == flat[i]
  for i in hits..<indexed.len: doAssert indexed[i] == -7
  if hits <= 32: doAssert stats.orderScans == 0
  if hits >= 256: doAssert stats.orderScans == poses.len
echo "Grid sparse heapsort / dense transitions / untouched tail PASS"
