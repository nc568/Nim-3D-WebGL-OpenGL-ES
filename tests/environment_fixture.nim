## Shared WebGL/GLES pixel oracles; synthetic small horizontal receiver plane.
import std/math
import softgfx
import instance_fixture

func encoded(x: float64): int =
  int(round(255*(if x <= 0.0031308: x*12.92 else: 1.055*pow(x,1.0/2.4)-0.055)))

proc runEnvironmentProbe*(ctx: Context; caps: Capabilities; read: FrameReader) =
  var mesh: MeshData
  for pos in [[-1'f32,0,-1],[1'f32,0,-1],[1'f32,0,1],[-1'f32,0,1]]:
    mesh.vertices.add Vertex(position:pos,normal:[0'f32,1,0],color:[0.4'f32,0.4,0.4])
  mesh.indices = @[0'u16,1,2,0,2,3]
  var matrix = identity()
  matrix[5] = 0
  matrix[6] = 1
  matrix[9] = 1
  matrix[10] = 0
  var r = initRenderer(ctx,caps,mesh,unlit=true)
  r.render(64,64,matrix)
  let baseline = read()
  var effects: SceneEffects
  effects.blobCount = 2
  effects.blobs[0] = BlobShadow(center:[0'f32,0,0],radiusX:0.5,radiusZ:0.75,yaw:0.4,strength:0.5)
  effects.blobs[1] = BlobShadow(center:[0.15'f32,0,0],radiusX:0.3,radiusZ:0.3,strength:0.3)
  r.updateEffects(effects)
  r.render(64,64,matrix)
  let shadowed = read()
  doAssert shadowed != baseline
  for y in 0..<64:
    for x in 0..<64:
      var light = 0.4
      for i in 0..<effects.blobCount:
        let b = effects.blobs[i]
        let dx = (float64(x)+0.5)/32-1-float64(b.center[0])
        let dz = (float64(y)+0.5)/32-1-float64(b.center[2])
        let c = cos(float64(b.yaw))
        let s = sin(float64(b.yaw))
        let u = (c*dx-s*dz)/float64(b.radiusX)
        let v = (s*dx+c*dz)/float64(b.radiusZ)
        let t = clamp((u*u+v*v-0.15)/0.85,0.0,1.0)
        light *= 1-float64(b.strength)*(1-t*t*(3-2*t))
      for channel in 0..2:
        doAssert abs(int(shadowed[(y*64+x)*4+channel])-encoded(light)) <= 3,
          "Blob world-space/rotation/linear-color oracle differs"
  # Invalid updates must leave the previous uniforms intact.
  var invalid = effects
  invalid.blobs[1].strength = Inf.float32
  var rejected = false
  try: r.updateEffects(invalid)
  except ValueError: rejected = true
  doAssert rejected
  r.render(64,64,matrix)
  doAssert read() == shadowed
  for i in 0..1: effects.blobs[i].center[1] = 0.2
  r.updateEffects(effects)
  r.render(64,64,matrix)
  doAssert read() == baseline, "Blob shadow leaked onto another receiver height"
  effects = SceneEffects(fogEnabled:true,fogNear:0,fogFar:0.1,fogColor:[0.1'f32,0.2,0.3])
  r.updateEffects(effects)
  r.render(64,64,matrix)
  let fogged = read()
  for pixel in 0..<64*64:
    for c in 0..2:
      doAssert abs(int(fogged[pixel*4+c])-encoded(float64(effects.fogColor[c]))) <= 2,
        "Fog should mix linear RGB before sRGB encode"
  effects.fogFar = sqrt(8.0).float32 # equal corner distances -> interpolated factor .5
  r.updateEffects(effects)
  r.render(64,64,matrix)
  let halfFog = read()
  for pixel in 0..<64*64:
    for c in 0..2:
      doAssert abs(int(halfFog[pixel*4+c])-encoded(0.2+float64(effects.fogColor[c])*0.5)) <= 3
  r.updateEffects(SceneEffects())
  r.render(64,64,matrix)
  doAssert read() == baseline
  # Enabled fog/blobs must use transformed world positions in both instance paths.
  effects = SceneEffects(fogEnabled:true,fogFar:4,fogColor:[0.1'f32,0.2,0.3],blobCount:1)
  effects.blobs[0] = BlobShadow(radiusX:0.5,radiusZ:0.7,strength:0.5)
  var transformed: MeshData
  transformed.indices = mesh.indices
  for v in mesh.vertices:
    var output = v
    output.position = [v.position[0]*0.5'f32+0.25'f32,0'f32,v.position[2]*0.5'f32+0.125'f32]
    transformed.vertices.add output
  var reference = initRenderer(ctx,caps,transformed,unlit=true)
  reference.updateEffects(effects)
  reference.render(64,64,matrix)
  let expectedInstances = read()
  for fallback in [false,true]:
    var batch = initRenderer(ctx,caps,mesh,instanceCapacity=1,forceFallback=fallback,unlit=true)
    batch.updateInstances(@[instance([0.25'f32,0,0.125],scale=0.5)])
    batch.updateEffects(effects)
    batch.renderInstances(64,64,matrix)
    let image = read()
    for i in 0..<image.len: doAssert abs(int(image[i])-int(expectedInstances[i])) <= 2
    batch.dispose()
  reference.dispose()
  # Sky must fill the depth16 FBO, and MUST NOT occlude later geometry.
  var sky = initSkyRenderer(ctx,caps,[0.6'f32,0.7,0.8],[0.1'f32,0.2,0.4])
  var farMesh = mesh
  # Explicit independent vertices (JS seq assignment can share storage).
  farMesh.vertices = newSeq[Vertex](mesh.vertices.len)
  for i in 0..<mesh.vertices.len:
    farMesh.vertices[i] = mesh.vertices[i]
    farMesh.vertices[i].color = [0.1'f32,0.2,0.8]
  var far = initRenderer(ctx,caps,farMesh,unlit=true)
  var p = initPipeline(ctx,caps)
  var neutral = defaultPost()
  neutral.fxaa = false
  neutral.dither = false
  doAssert p.beginFrame(64,64,neutral)
  sky.renderBackground(64,64)
  let gradient = read() # current framebuffer; native and browser read the FBO
  doAssert gradient[0] > gradient[(63*64)*4]+50
  for y in 0..<64:
    let t = (float64(y)+0.5)/64
    for c in 0..2:
      let bottom = [0.6,0.7,0.8][c]
      let top = [0.1,0.2,0.4][c]
      doAssert abs(int(gradient[(y*64+32)*4+c])-encoded(bottom*(1-t)+top*t)) <= 3,
        "Sky must interpolate linear RGB before encoding"
  r.render(64,64,matrix,clear=false)
  var farMatrix = matrix
  farMatrix[14] = 0.5
  far.render(64,64,farMatrix,clear=false)
  p.endFrame()
  let composed = read()
  for i in 0..<composed.len: doAssert abs(int(composed[i])-int(baseline[i])) <= 1
  p.dispose()
  far.dispose()
  sky.dispose()
  r.dispose()
  echo "Environment fog/blob/sky/depth/state oracles PASS: ",caps.api
