## Same pixel/lifecycle oracle for WebGL and native GLES. No GPU timing claims.
import softgfx, softgfx/geometry
import instance_fixture, fxaa_reference

proc runPostProbe*(ctx: Context; caps: Capabilities; read: FrameReader) =
  var mesh: MeshData
  mesh.addBox([0'f32,0,0],[0.63'f32,0.51,0.2],[0.8'f32,0.3,0.1])
  var r = initRenderer(ctx,caps,mesh.indexed())
  var p = initPipeline(ctx,caps)
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
  p = initPipeline(ctx,caps,maxTargetPixels=64*64)
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
  p.dispose()
  alias = p
  p.abandon()
  alias.cancelFrame()
  alias.dispose()
  r.dispose()
  echo "Post neutral/scale/grading/lifecycle PASS: ",caps.api
