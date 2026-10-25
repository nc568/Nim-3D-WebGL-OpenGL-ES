## Shared-handle frame scope. Aliases share state/disposal, not independent frames.
## One pipeline at a time per context; no foreign framebuffer/VAO interleaving.
import ./[types, post_types, scopes]
export post_types, scopes
when defined(js):
  import ./backends/web as backend
else:
  import ./backends/gles as backend

type Pipeline* = ref object
  scopes: ContextScopes
  owner: ScopeOwner
  context: backend.Context
  target: backend.PostTarget
  post: backend.PostPass
  alive, modern, active, offscreen, postReady: bool
  limit, budget, tw, th, w, h, rw, rh: int
  settings: PostSettings
  stats*: PipelineStats

proc initPipeline*(context: backend.Context; caps: Capabilities;
                   maxTargetPixels = DefaultTargetPixels; scopes: ContextScopes = nil): Pipeline =
  if maxTargetPixels < 1 or maxTargetPixels > high(int32) div 6:
    raise newException(ValueError,"Invalid post pixel budget")
  scopes.requireContext()
  new(result)
  result.scopes = scopes
  result.owner = newScopeOwner()
  result.context = context
  result.modern = caps.api in {webgl2,gles3}
  result.budget = maxTargetPixels
  if result.modern: result.limit = backend.targetLimit(context)
  result.alive = true

proc renderSize*(p: Pipeline): SurfaceSize =
  if p.isNil or not p.alive: raise newException(ValueError,"Pipeline is disposed")
  p.scopes.requireContext()
  (p.rw,p.rh)

proc postUniformStats*(p: Pipeline): tuple[calls, skips: int] =
  if p.isNil or not p.alive: raise newException(ValueError,"Pipeline is disposed")
  if p.postReady: (p.post.uniformCache.calls,p.post.uniformCache.skips)
  else: (0,0)

proc invalidatePostUniforms*(p: Pipeline) =
  ## Use after external mutation of this post program's five dynamic uniforms.
  if p.isNil or not p.alive: raise newException(ValueError,"Pipeline is disposed")
  if p.postReady: p.post.uniformCache.valid = false

proc beginFrameImpl(p: var Pipeline; width,height: int;
                 settings = defaultPost()): bool =
  ## Returns false for a minimized/zero-sized surface. Scene draws within this
  ## scope MUST use renderSize and clear=false. Camera aspect uses OUTPUT size.
  if p.isNil or not p.alive: raise newException(ValueError,"Pipeline is disposed")
  if p.active: raise newException(ValueError,"Frame already active")
  settings.validate()
  let scaled = scaledSize(width,height,settings.scale)
  let offscreen = p.modern and settings.enabled
  let size = if offscreen: scaled else: (width,height)
  if width > 0 and height > 0 and offscreen:
    if size.width > p.limit or size.height > p.limit or size.width > p.budget div size.height:
      raise newException(ValueError,"Post target exceeds device limit or pixel budget")
    if not p.postReady:
      p.post = backend.createPost(p.context)
      p.postReady = true
    if size.width != p.tw or size.height != p.th:
      # Allocate/check first: failed resize preserves the last good allocation.
      var next = backend.createTarget(p.context,size.width,size.height)
      backend.destroyTarget(p.context,p.target)
      p.target = next
      p.tw = size.width
      p.th = size.height
      p.stats.allocatedBytes = p.tw*p.th*6 # RGBA8 + depth16, excludes driver padding
      if p.stats.targetRebuilds < high(int): inc p.stats.targetRebuilds
  p.w = width
  p.h = height
  p.rw = if width == 0 or height == 0: 0 else: size.width
  p.rh = if width == 0 or height == 0: 0 else: size.height
  p.offscreen = offscreen and p.rw > 0
  p.settings = settings
  p.stats.renderWidth = p.rw
  p.stats.renderHeight = p.rh
  p.stats.outputWidth = width
  p.stats.outputHeight = height
  p.stats.offscreen = p.offscreen
  p.stats.finalDrawCalls = 0
  if p.rw == 0: return false
  try: backend.beginTarget(p.context,p.target,p.offscreen,p.rw,p.rh)
  except:
    p.scopes.invalidate()
    raise
  p.active = true
  true

proc beginFrame*(p: var Pipeline; width,height: int;
                 settings = defaultPost()): bool =
  if p.isNil or not p.alive: raise newException(ValueError,"Pipeline is disposed")
  if p.active: raise newException(ValueError,"Frame already active")
  p.scopes.claim(frameScope,p.owner)
  try:
    result = p.beginFrameImpl(width,height,settings)
  finally:
    if not p.active: p.scopes.release(frameScope,p.owner)

proc cancelFrame*(p: var Pipeline) =
  ## No presentation; useful in finally after an exception. Idempotent.
  if not p.isNil and p.active:
    try:
      p.scopes.requireContext()
      backend.defaultTarget(p.context)
    except:
      p.scopes.invalidate()
      raise
    finally:
      p.active = false
      p.scopes.release(frameScope,p.owner)

proc endFrame*(p: var Pipeline) =
  if p.isNil or not p.alive or not p.active: raise newException(ValueError,"No active frame")
  p.scopes.requireContext()
  try:
    if p.offscreen:
      backend.present(p.context,p.post,p.target,p.w,p.h,p.rw,p.rh,p.settings)
      p.stats.finalDrawCalls = 1
    else:
      backend.defaultTarget(p.context)
  finally:
    p.cancelFrame()

proc dispose*(p: var Pipeline) =
  if p.isNil or not p.alive: return
  p.scopes.claim(frameScope,p.owner) # reject foreign active frame before GL calls
  p.alive = false
  try:
    p.cancelFrame()
    backend.destroyTarget(p.context,p.target)
    backend.destroyPost(p.context,p.post)
    p.stats.allocatedBytes = 0
  finally:
    p.scopes.release(frameScope,p.owner)

proc abandon*(p: var Pipeline) =
  ## Context LOST only: forget invalid handles without issuing any GL calls.
  ## Recreate with initPipeline on the restored context.
  if p.isNil: return
  p.scopes.invalidate()
  p.alive = false
  p.active = false
  p.postReady = false
  p.stats.allocatedBytes = 0
