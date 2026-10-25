## Provisional game-like browser workloads. Not authoritative game limits or FPS.
import std/[jsffi, json]
import softgfx, softgfx/[culling, geometry]
import softgfx/backends/web
import ../examples/scene
proc canvas(): JsObject {.importjs: "document.getElementById('scene')".}
proc legacy(): bool {.importjs: "(new URLSearchParams(location.search).has('webgl1'))".}
let device = acquire(canvas(),legacy())
let carAsset = carMesh(device.caps.api == webgl1)
let arenaAsset = arenaMesh(device.caps.api == webgl1,includeCars=false)
let bounds = carAsset.meshBounds()
var ground, cars: Renderer
var pipeline: Pipeline
var poses: seq[Instance]
var indices, flat: seq[int]
var grid: SpatialGrid
var query: GridQueryStats
var matrix: Mat4
var settings: PostSettings
var count, visible, steps, deltas, selectedCount: int
var live = false
proc require(ok: bool) =
  if not ok: raise newException(ValueError,"Soak contract failed")
proc stop() =
  if not live: return
  pipeline.dispose(); cars.dispose(); ground.dispose()
  live = false
proc start(n: int; fallback: bool) =
  require(not live and n in [64,256,1024])
  count = n; steps = 0; deltas = 0
  poses = newSeq[Instance](count)
  indices = newSeq[int](count); flat = newSeq[int](count)
  let side = if n == 64: 8 elif n == 256: 16 else: 32
  for i in 0..<count:
    poses[i] = instance([float32(i mod side)*1.5'f32-float32(side-1)*0.75'f32,0,
      float32(i div side)*1.5'f32-float32(side-1)*0.75'f32],
      yaw=float32(i mod 11)*0.1'f32,scale=0.45'f32,
      tint=[0.3'f32+float32(i mod 5)*0.1'f32,0.5'f32,0.6'f32])
  grid = initSpatialGrid(Bounds(lower:[-30.0,-2.0,-30.0],upper:[30.0,4.0,30.0]),[8,1,8],count)
  # Cleanup partial initialization too; no context-loss shortcuts here.
  try:
    ground = initRenderer(device.ctx,device.caps,arenaAsset,arenaOwners())
    cars = initRenderer(device.ctx,device.caps,carAsset,instanceCapacity=count,forceFallback=fallback)
    pipeline = initPipeline(device.ctx,device.caps)
    live = true
  except:
    pipeline.dispose(); cars.dispose(); ground.dispose()
    raise
proc draw(selected: bool) =
  if selected: discard cars.updateVisibleInstancesIfChanged(poses,indices,selectedCount)
  else: cars.updateInstances(poses)
  require(pipeline.beginFrame(192,128,settings))
  try:
    let size = pipeline.renderSize()
    ground.render(size.width,size.height,matrix,clear=false)
    cars.renderInstances(size.width,size.height,matrix,clear=false)
    pipeline.endFrame()
  finally: pipeline.cancelFrame()
proc step(tick: int): cstring =
  require(live and tick == steps)
  # Alternating stationary, sparse and fully moving snapshots, bounded excursion.
  if tick mod 4 in [1,2]:
    for i in 0..<count:
      if tick mod 4 == 2 or i mod 16 == 0:
        poses[i].yaw += 0.025'f32
        poses[i].position[0] += (if tick mod 8 < 4: 0.02'f32 else: -0.02'f32)
  if tick mod 12 == 0:
    let patch = newSeqWithOwner(6,uint8(1+(tick div 12) mod 3))
    ground.updateTerritory((tick div 12) mod 28,(tick div 12) mod 21,3,2,patch)
    inc deltas
  matrix = arenaCamera(angle=0.6'f32+float32(tick mod 96)*0.003'f32,
    distance=(if (tick div 24) mod 2 == 0: 18'f32 else: 45'f32)).viewProjection(1.5'f32)
  grid.rebuild(bounds,poses)
  let view = frustum(matrix)
  visible = view.collectVisible(grid,indices,query)
  require(view.collectVisible(bounds,poses,flat) == visible)
  for i in 0..<visible: require(indices[i] == flat[i])
  selectedCount = visible
  if (tick div 16) mod 2 == 1:
    selectedCount = count
    for i in 0..<count: indices[i] = i
  settings = defaultPost()
  settings.enabled = tick mod 48 < 32
  settings.scale = if (tick div 12) mod 2 == 0: 1'f32 else: 0.7'f32
  settings.fxaa = (tick div 24) mod 2 == 0
  settings.dither = false
  draw(true)
  require(cars.stats.instances == selectedCount)
  require(cars.stats.drawCalls == (if cars.instanceMode == fallbackDraws: selectedCount else: int(selectedCount > 0)))
  require(ground.stats.deltaUploads == deltas and ground.stats.deltaBytes == deltas*6)
  inc steps
  result = cstring($(%*{"api": $device.caps.api,"instances":count,"tick":tick,
    "visible":visible,"submitted":selectedCount,"mode": $cars.instanceMode,
    "drawCalls":ground.stats.drawCalls+cars.stats.drawCalls+pipeline.stats.finalDrawCalls,
    "targetBytes":pipeline.stats.allocatedBytes,"targetRebuilds":pipeline.stats.targetRebuilds,
    "territoryDeltas":deltas,"territoryBytes":ground.stats.deltaBytes,
    "instanceUploadBytes":cars.stats.instanceUploadBytes}))
proc reference() =
  require(live and steps > 0)
  draw(false)
proc publish(a: proc(n: int; fallback: bool); b: proc(tick: int): cstring;
             c,d: proc()) {.importjs: "(function(a,b,c,d){globalThis.softgfxSoak={start:a,step:b,reference:c,stop:d};})(#,#,#,#)".}
publish(start,step,reference,stop)
