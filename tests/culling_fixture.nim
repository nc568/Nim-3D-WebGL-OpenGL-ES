import softgfx, softgfx/[culling, geometry]
import instance_fixture

proc runCullingProbe*(ctx: Context; caps: Capabilities; read: FrameReader) =
  var mesh: MeshData
  mesh.addBox([0'f32,0,0],[0.4'f32,0.5,0.3],[0.6'f32,0.3,0.1])
  mesh = mesh.indexed()
  let bounds = mesh.meshBounds()
  var poses = newSeq[Instance](41)
  var indices = newSeq[int](poses.len)
  var grid = initSpatialGrid(Bounds(lower:[-8.0,-2.0,-2.0],upper:[8.0,2.0,2.0]),[8,2,2],poses.len)
  var gridIndices = newSeq[int](poses.len)
  var gridStats: GridQueryStats
  for fallback in [false,true]:
    var all = initRenderer(ctx,caps,mesh,instanceCapacity=poses.len,forceFallback=fallback)
    var selected = initRenderer(ctx,caps,mesh,instanceCapacity=poses.len,forceFallback=fallback)
    for tick in 0..<20:
      for i in 0..<poses.len:
        poses[i] = instance([float32(i-20)*0.35'f32+float32(tick)*0.03'f32,
          float32(i mod 3-1)*0.25'f32,0'f32],yaw=float32(i)*0.2'f32,scale=0.5'f32+float32(i mod 4)*0.2'f32)
      var matrix = identity()
      if tick mod 2 == 1:
        matrix = Camera(eye:[2'f32,2,4],target:[0'f32,0,0],up:[0'f32,1,0],
          fovY:0.8,nearPlane:0.1,farPlane:20).viewProjection(1)
      let count = frustum(matrix).collectVisible(bounds,poses,indices)
      grid.rebuild(bounds,poses)
      doAssert frustum(matrix).collectVisible(grid,gridIndices,gridStats) == count
      for i in 0..<count: doAssert gridIndices[i] == indices[i]
      doAssert count > 0 and count < poses.len
      all.updateInstances(poses)
      all.renderInstances(64,64,matrix)
      let reference = read()
      selected.updateVisibleInstances(poses,gridIndices,count)
      selected.renderInstances(64,64,matrix)
      doAssert read() == reference, "Frustum culling changed visible pixels"
      doAssert selected.stats.instances == count
      let oldUpdates = selected.stats.instanceUpdates
      var rejected = false
      try: selected.updateVisibleInstances(poses,[0,0],2)
      except ValueError: rejected = true
      doAssert rejected and selected.stats.instanceUpdates == oldUpdates
      selected.renderInstances(64,64,matrix)
      doAssert read() == reference
    selected.updateVisibleInstances(poses,indices,0)
    selected.renderInstances(64,64,clear=false)
    doAssert selected.stats.drawCalls == 0
    all.dispose()
    selected.dispose()
  echo "Culling GPU pixel parity/selection lifecycle PASS: ",caps.api
