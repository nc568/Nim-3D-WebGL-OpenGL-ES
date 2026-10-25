import softgfx/[types, shaders, math3d, territory, instances, pipeline, environment]
export types, math3d, territory, instances, pipeline, environment
when defined(js):
  import softgfx/backends/web as backend
else:
  import softgfx/backends/gles as backend
export backend.Context

type Renderer* = ref object
  context: Context
  program: backend.Program
  buffer, indices: backend.Buffer
  territoryBinding: backend.TerritoryBinding
  owners: OwnerMap
  indexed: bool
  effectBinding: backend.EffectBinding
  effects: SceneEffects
  effectsDelta: EffectChanges
  effectsUncertain, instancesPending: bool
  matrixBinding: backend.MatrixBinding
  stream: backend.InstanceStream
  instanceData: seq[float32]
  instanceRange: InstanceRange
  instanceCount, instanceCapacity: int
  count: int
  alive, background: bool
  caps*: Capabilities
  stats*: FrameStats

proc initRenderer*(context: Context; caps: Capabilities; mesh: MeshData; owners: OwnerMap = nil; instanceCapacity = 0; forceFallback = false; unlit = false; background = false): Renderer =
  mesh.validate()
  if background and instanceCapacity != 0:
    raise newException(ValueError,"Background shader does not support instances")
  if instanceCapacity < 0 or instanceCapacity > MaxInstances:
    raise newException(ValueError, "Invalid instance capacity")
  new(result)
  result.context = context
  result.caps = caps
  result.owners = if owners.isNil: newOwnerMap(1,1) else: owners
  result.background = background
  result.program = backend.createProgram(context,
    (if background: skyVertexSource(caps.api) else: vertexSource(caps.api)),
    (if background: skyFragmentSource(caps.api) else: fragmentSource(caps.api,unlit)))
  try:
    result.territoryBinding = backend.createTerritory(context, result.program, caps.api in {webgl2,gles3}, result.owners)
    result.buffer = backend.createBuffer(context, mesh.packed())
    result.indices = backend.createIndices(context, mesh.indices)
    result.effectBinding = backend.effectBinding(context,result.program)
    result.matrixBinding = backend.matrixBinding(context, result.program)
    result.indexed = mesh.indices.len > 0
    result.count = if result.indexed: mesh.indices.len else: mesh.vertices.len
    result.stats.bufferBytes = mesh.vertices.len * 48 + mesh.indices.len * 2
    result.stats.textureBytes = result.owners.width * result.owners.height + 1024
    if instanceCapacity > 0:
      result.stream = backend.createInstanceStream(context,caps.api,instanceCapacity,forceFallback)
      var packedShadow = newInstanceData(instanceCapacity)
      when defined(js):
        # Nim field assignment (even move) copies seqs into Float64Array.
        {.emit: "`result`.instanceData = `packedShadow`;".}
      else: result.instanceData = move(packedShadow)
      result.instanceCapacity = instanceCapacity
      if result.stream.mode != fallbackDraws:
        result.stats.bufferBytes += instanceCapacity*InstanceBytes
    result.alive = true
  except:
    backend.destroyInstanceStream(context,result.stream)
    backend.destroyIndices(context,result.indices)
    backend.destroyTerritory(context,result.territoryBinding)
    backend.destroy(context,result.program,result.buffer)
    raise

proc countBytes(counter: var int; amount: int) {.inline.} =
  # Counters must not crash long-running sessions (Nim JS int is checked int32).
  if amount > high(int)-counter: counter = high(int)
  else: counter += amount

proc updateTerritory*(r: var Renderer; x,y,w,h: int; data: seq[uint8]) =
  ## Tight byte rows. CPU shadow is retained for context recreation.
  if r.isNil or not r.alive: raise newException(ValueError, "Renderer is disposed")
  r.owners.checkDelta(x,y,w,h,data)
  backend.uploadDelta(r.context,r.territoryBinding,x,y,w,h,data)
  r.owners.applyDelta(x,y,w,h,data)
  countBytes(r.stats.deltaUploads,1)
  countBytes(r.stats.deltaBytes,data.len)

proc instanceMode*(r: Renderer): InstanceMode =
  if r.isNil or not r.alive: raise newException(ValueError,"Renderer is disposed")
  r.stream.mode

proc cameraStats*(r: Renderer): tuple[uploads, skips: int] =
  if r.isNil or not r.alive: raise newException(ValueError,"Renderer is disposed")
  (r.matrixBinding.uploads,r.matrixBinding.skips)

proc invalidateCamera*(r: Renderer) =
  ## Required if external GL code mutates this program's camera uniform.
  if r.isNil or not r.alive: raise newException(ValueError,"Renderer is disposed")
  backend.invalidateMatrix(r.matrixBinding)

proc updateInstances*(r: var Renderer; items: openArray[Instance]) =
  if r.isNil or not r.alive: raise newException(ValueError, "Renderer is disposed")
  if r.instanceCapacity == 0: raise newException(ValueError, "Renderer has no instance capacity")
  if items.len > 0 and r.count > high(int) div items.len:
    raise newException(ValueError, "Submitted vertex statistics exceed host integer range")
  packInstances(items,r.instanceData)
  r.instancesPending = true
  backend.uploadInstances(r.context,r.stream,r.instanceData,items.len)
  r.instancesPending = false
  r.instanceCount = items.len
  countBytes(r.stats.instanceUpdates,1)
  if r.stream.mode != fallbackDraws:
    countBytes(r.stats.instanceUploadBytes,items.len*InstanceBytes)

proc frameReady(r: var Renderer; width,height: int; viewProjection: Mat4): bool =
  if r.isNil or not r.alive: raise newException(ValueError, "Renderer is disposed")
  r.stats.drawCalls = 0
  r.stats.vertices = 0
  r.stats.instances = 0
  if width <= 0 or height <= 0: return false
  if width > high(int32).int or height > high(int32).int:
    raise newException(ValueError, "Surface exceeds GLsizei")
  for value in viewProjection:
    if not finite(value): raise newException(ValueError, "Non-finite view-projection matrix")
  true

proc render*(r: var Renderer; width, height: int; viewProjection = identity(); clear = true) =
  ## clear=false composes another opaque batch into the current color/depth target.
  if not r.isNil and r.background: raise newException(ValueError,"Use renderBackground for a sky renderer")
  if not r.frameReady(width,height,viewProjection): return
  backend.draw(r.context, r.program, r.buffer, r.count, width, height, r.matrixBinding,
    viewProjection, r.indices, r.indexed, r.territoryBinding, clear)
  r.stats.drawCalls = 1
  r.stats.vertices = r.count

proc renderInstances*(r: var Renderer; width, height: int; viewProjection = identity(); clear = true) =
  if not r.frameReady(width,height,viewProjection): return
  if r.instanceCapacity == 0: raise newException(ValueError, "Renderer has no instance capacity")
  backend.drawInstances(r.context,r.program,r.buffer,r.count,width,height,r.matrixBinding,
    viewProjection,r.indices,r.indexed,r.territoryBinding,r.stream,r.instanceData,r.instanceCount,clear)
  r.stats.instances = r.instanceCount
  r.stats.drawCalls = if r.stream.mode == fallbackDraws: r.instanceCount else: int(r.instanceCount > 0)
  r.stats.vertices = r.count*r.instanceCount

proc dispose*(r: var Renderer) =
  ## Shared handle: all aliases observe disposal. Original context must be current.
  if not r.isNil and r.alive:
    r.alive = false # invalidate aliases BEFORE issuing driver calls
    try: backend.destroyInstanceStream(r.context,r.stream)
    finally:
      r.instanceData = @[]
      r.stream = default(backend.InstanceStream)
    backend.destroyIndices(r.context,r.indices)
    backend.destroyTerritory(r.context,r.territoryBinding)
    backend.destroy(r.context, r.program, r.buffer)


proc abandon*(r: var Renderer) =
  ## Context LOST only. No GL calls; all aliases become invalid.
  if r.isNil: return
  r.alive = false
  r.instanceData = @[]
  r.stream = default(backend.InstanceStream)

proc updateEffects*(r: var Renderer; settings: SceneEffects; force = false) =
  if r.isNil or not r.alive: raise newException(ValueError,"Renderer is disposed")
  if r.background: raise newException(ValueError,"Background shader does not accept scene effects")
  settings.validate() # reject entire snapshot before mutating any uniform
  if not effectChanges(r.effects,settings,r.effectsDelta,force or r.effectsUncertain):
    countBytes(r.stats.effectSkippedUpdates,1)
    return
  r.effectsUncertain = true # exceptions during upload require a complete retry
  let calls = backend.updateEffects(r.context,r.program,r.effectBinding,settings,r.effectsDelta)
  retainEffects(settings,r.effects)
  r.effectsUncertain = false
  countBytes(r.stats.effectUpdates,1)
  countBytes(r.stats.effectUniformCalls,calls)

proc renderBackground*(r: var Renderer; width,height: int) =
  ## Clip-space opaque background. Caller clears once first; draw BEFORE scene.
  ## Depth testing/writes are disabled for this draw, restored by next scene draw.
  if not r.frameReady(width,height,identity()): return
  backend.draw(r.context,r.program,r.buffer,r.count,width,height,r.matrixBinding,
    identity(),r.indices,r.indexed,r.territoryBinding,false,background=true)
  r.stats.drawCalls = 1
  r.stats.vertices = r.count


proc initSkyRenderer*(context: Context; caps: Capabilities; bottom,top: Vec3): Renderer =
  ## Minimal clip-space gradient shader; no texture sampling/lighting/blob loop.
  initRenderer(context,caps,skyMesh(bottom,top),background=true)

proc updateVisibleInstances*(r: var Renderer; items: openArray[Instance];
                             indices: openArray[int]; count: int) =
  ## Packs the index prefix directly; no temporary seq[Instance]/slice required.
  if r.isNil or not r.alive: raise newException(ValueError,"Renderer is disposed")
  if r.instanceCapacity == 0: raise newException(ValueError,"Renderer has no instance capacity")
  if count > 0 and r.count > high(int) div count:
    raise newException(ValueError,"Submitted vertex statistics exceed host integer range")
  packVisible(items,indices,count,r.instanceData)
  r.instancesPending = true
  backend.uploadInstances(r.context,r.stream,r.instanceData,count)
  r.instancesPending = false
  r.instanceCount = count
  countBytes(r.stats.instanceUpdates,1)
  if r.stream.mode != fallbackDraws:
    countBytes(r.stats.instanceUploadBytes,count*InstanceBytes)


proc finishConditionalUpdate(r: var Renderer; count: int): bool =
  if r.instanceRange.last <= r.instanceRange.first and not r.instancesPending and count == r.instanceCount:
    countBytes(r.stats.instanceSkippedUpdates,1)
    return false
  let full = r.instancesPending or count != r.instanceCount
  let first = if full: 0 else: r.instanceRange.first
  let length = if full: count else: r.instanceRange.last-first
  r.instancesPending = true
  backend.uploadInstancesRange(r.context,r.stream,r.instanceData,first,length)
  r.instancesPending = false
  r.instanceCount = count
  countBytes(r.stats.instanceUpdates,1)
  if r.stream.mode != fallbackDraws:
    countBytes(r.stats.instanceUploadBytes,length*InstanceBytes)
  true

proc updateInstancesIfChanged*(r: var Renderer; items: openArray[Instance]): bool {.discardable.} =
  ## Still O(N) validation/packing; skips GPU submission for identical float32 data.
  if r.isNil or not r.alive: raise newException(ValueError,"Renderer is disposed")
  if r.instanceCapacity == 0: raise newException(ValueError,"Renderer has no instance capacity")
  if items.len > 0 and r.count > high(int) div items.len:
    raise newException(ValueError,"Submitted vertex statistics exceed host integer range")
  packInstancesRange(items,r.instanceData,r.instanceRange)
  r.finishConditionalUpdate(items.len)

proc updateVisibleInstancesIfChanged*(r: var Renderer; items: openArray[Instance];
                                     indices: openArray[int]; count: int): bool {.discardable.} =
  if r.isNil or not r.alive: raise newException(ValueError,"Renderer is disposed")
  if r.instanceCapacity == 0: raise newException(ValueError,"Renderer has no instance capacity")
  if count > 0 and r.count > high(int) div count:
    raise newException(ValueError,"Submitted vertex statistics exceed host integer range")
  packVisibleRange(items,indices,count,r.instanceData,r.instanceRange)
  r.finishConditionalUpdate(count)
