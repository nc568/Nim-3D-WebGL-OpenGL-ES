## Same pixel/lifecycle oracle for WebGL and native GLES. No GPU timing claims.
import softgfx, softgfx/geometry
import instance_fixture, fxaa_reference

when defined(js):
  proc trackPost(gl: Context) {.importjs: """(function(g){const names=['uniform1f','uniform1i','uniform2f'],old=names.map(n=>g[n]);g._postCalls=0;g._postFail=0;g._postAfter=false;g._restorePost=()=>names.forEach((n,i)=>g[n]=old[i]);names.forEach((n,i)=>g[n]=function(...a){g._postCalls++;const fail=--g._postFail===0;if(fail&&!g._postAfter)throw Error('post before');const v=old[i].apply(g,a);if(fail)throw Error('post after');return v;});})(#)""".}
  proc postCalls(gl: Context): int {.importjs: "#._postCalls".}
  proc failPost(gl: Context; after: bool) {.importjs: "(function(g,a){g._postFail=2;g._postAfter=a;})(#,#)".}
  proc untrackPost(gl: Context) {.importjs: "#._restorePost()".}

proc cachedFrame(p: var Pipeline; r: var Renderer; s: PostSettings) =
  doAssert p.beginFrame(64,64,s)
  let size = p.renderSize()
  r.render(size.width,size.height,clear=false)
  p.endFrame()

proc runPostCacheProbe(ctx: Context; caps: Capabilities; read: FrameReader) =
  if caps.api notin {webgl2,gles3}: return
  var mesh: MeshData
  mesh.addBox([0'f32,0,0],[0.63'f32,0.51,0.2],[0.8'f32,0.3,0.1])
  var r = initRenderer(ctx,caps,mesh)
  var p = initPipeline(ctx,caps)
  var s = defaultPost()
  p.cachedFrame(r,s)
  let initial = read()
  doAssert p.postUniformStats == (5,0)
  when defined(js): trackPost(ctx)
  try:
    for i in 0..<100: p.cachedFrame(r,s)
    doAssert p.postUniformStats == (5,500) and read() == initial
    when defined(js): doAssert postCalls(ctx) == 0
    for field in 0..<5:
      let before = p.postUniformStats.calls
      case field
      of 0: s.exposure = 0.6
      of 1: s.vignette = 0.4
      of 2: s.fxaa = false
      of 3: s.dither = false
      else: s.scale = 0.8
      p.cachedFrame(r,s)
      doAssert p.postUniformStats.calls == before+1
      let partial = read()
      var alias = p
      alias.invalidatePostUniforms()
      p.cachedFrame(r,s)
      doAssert p.postUniformStats.calls == before+6 and read() == partial
    when defined(js):
      for after in [false,true]:
        p.invalidatePostUniforms()
        failPost(ctx,after)
        var rejected = false
        try: p.cachedFrame(r,s)
        except: rejected = true
        doAssert rejected
        let attempts = postCalls(ctx)
        p.cachedFrame(r,s)
        doAssert postCalls(ctx) == attempts+5
        let retried = read()
        p.invalidatePostUniforms()
        p.cachedFrame(r,s)
        doAssert read() == retried
    s.enabled = false
    let before = p.postUniformStats
    p.cachedFrame(r,s)
    doAssert p.postUniformStats == before
    s.enabled = true
    p.cachedFrame(r,s)
    doAssert p.postUniformStats.calls == before.calls
  finally:
    when defined(js): untrackPost(ctx)
    p.dispose(); r.dispose()
  echo "Post uniform cache / 500 skipped calls / field masks / force parity / retry PASS: ",caps.api

proc runPostProbe*(ctx: Context; caps: Capabilities; read: FrameReader) =
  runPostCacheProbe(ctx,caps,read)
  var mesh: MeshData
  mesh.addBox([0'f32,0,0],[0.63'f32,0.51,0.2],[0.8'f32,0.3,0.1])
  var r = initRenderer(ctx,caps,mesh.indexed())
  let scopes = newContextScopes()
  var p = initPipeline(ctx,caps,scopes=scopes)
  var neutral = defaultPost()
  neutral.fxaa = false
  neutral.dither = false
  r.render(64,64)
  let direct = read()
  doAssert p.beginFrame(64,64,neutral)
  let size = p.renderSize()
  r.render(size.width,size.height,clear=false)
  p.endFrame()
  let copied = read()
  for i in 0..<direct.len:
    doAssert abs(int(direct[i])-int(copied[i])) <= 1, "Neutral pass changed encoded color"
  let modern = caps.api in {webgl2,gles3}
  doAssert p.stats.finalDrawCalls == ord(modern)
  doAssert p.stats.allocatedBytes == (if modern: 64*64*6 else: 0)
  for scale in [0.7'f32,0.8,0.9,1]:
    neutral.scale = scale
    doAssert p.beginFrame(64,64,neutral)
    let size = p.renderSize()
    doAssert size == (if modern: scaledSize(64,64,scale) else: (64,64))
    r.render(size.width,size.height,clear=false)
    p.endFrame()
    let image = read()
    doAssert image[3] == 255
  let rebuilds = p.stats.targetRebuilds
  doAssert p.beginFrame(64,64,neutral)
  p.endFrame()
  doAssert p.stats.targetRebuilds == rebuilds
  # Disabled path retains its cache but neither scales nor presents.
  neutral.enabled = false
  neutral.scale = 0.7
  doAssert p.beginFrame(64,64,neutral)
  doAssert p.renderSize() == (64,64)
  r.render(64,64,clear=false)
  p.endFrame()
  doAssert p.stats.finalDrawCalls == 0 and read() == direct
  doAssert not p.beginFrame(0,64,neutral)
  doAssert p.stats.finalDrawCalls == 0
  doAssert p.beginFrame(64,64,neutral)
  var rejected = false
  try: discard p.beginFrame(64,64,neutral)
  except ValueError: rejected = true
  doAssert rejected
  p.cancelFrame()
  p.cancelFrame()
  # Exercise all post uniforms and check scene attribute/divisor recovery.
  var effects = defaultPost()
  effects.exposure = 0.5
  effects.vignette = 0.4
  doAssert p.beginFrame(64,64,effects)
  r.render(64,64,clear=false)
  p.endFrame()
  let graded = read()
  if modern:
    doAssert graded != copied
    doAssert graded[(32*64+32)*4] < copied[(32*64+32)*4]
  else: doAssert graded == direct
  r.render(64,64)
  doAssert read() == direct, "Post state leaked into scene renderer"
  if modern:
    # Isolate AA from grading and dither; compare every pixel to a CPU oracle.
    neutral = defaultPost()
    neutral.fxaa = false
    neutral.dither = false
    var rotation = identity()
    rotation[0] = 0.8
    rotation[1] = 0.6
    rotation[4] = -0.6
    rotation[5] = 0.8
    doAssert p.beginFrame(64,64,neutral)
    r.render(64,64,rotation,clear=false)
    p.endFrame()
    let diagonal = read()
    neutral.fxaa = true
    doAssert p.beginFrame(64,64,neutral)
    r.render(64,64,rotation,clear=false)
    p.endFrame()
    checkFxaa(diagonal,read())
    # Existing depth/composition/instance oracles now also run against depth16.
    doAssert p.beginFrame(64,64,neutral)
    runInstanceProbe(ctx,caps,read)
    p.endFrame()
  var alias = p
  alias.dispose()
  p.dispose()
  rejected = false
  try: discard p.beginFrame(64,64)
  except ValueError: rejected = true
  doAssert rejected
  p = initPipeline(ctx,caps,maxTargetPixels=64*64,scopes=scopes)
  rejected = false
  try: discard alias.beginFrame(64,64)
  except ValueError: rejected = true
  doAssert rejected
  doAssert p.beginFrame(64,64)
  p.endFrame()
  if modern:
    rejected = false
    try: discard p.beginFrame(65,64)
    except ValueError: rejected = true
    doAssert rejected and p.stats.targetRebuilds == 1
    doAssert p.beginFrame(64,64)
    p.endFrame()
    doAssert p.stats.targetRebuilds == 1
  alias = p
  doAssert alias.beginFrame(64,64)
  rejected = false
  try: discard p.beginFrame(64,64)
  except ValueError: rejected = true
  doAssert rejected # active state is shared, not copied
  p.endFrame()
  alias.cancelFrame()
  # Independent pipelines share one context guard. Rejection precedes allocation.
  var other = initPipeline(ctx,caps,scopes=scopes)
  doAssert p.beginFrame(64,64)
  let oldRebuilds = other.stats.targetRebuilds
  rejected = false
  try: discard other.beginFrame(64,64)
  except ValueError: rejected = true
  doAssert rejected and other.stats.targetRebuilds == oldRebuilds
  rejected = false
  try: other.dispose()
  except ValueError: rejected = true
  doAssert rejected
  p.endFrame()
  doAssert other.beginFrame(64,64)
  other.cancelFrame()
  doAssert not p.beginFrame(0,0) # no retained lock for a minimized surface
  doAssert other.beginFrame(64,64)
  other.endFrame()
  rejected = false
  try: discard p.beginFrame(-1,64)
  except ValueError: rejected = true
  doAssert rejected
  doAssert other.beginFrame(64,64)
  other.endFrame()
  other.dispose()
  p.dispose()
  alias = p
  p.abandon()
  alias.cancelFrame()
  alias.dispose()
  r.dispose()
  echo "Post neutral/scale/grading/lifecycle PASS: ",caps.api
