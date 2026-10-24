## Pixel comparisons shared by browser and native runs; no window-system dependencies.
import std/math
import softgfx, softgfx/geometry

type FrameReader* = proc(): seq[uint8] {.closure.}

proc baked(mesh: MeshData; items: openArray[Instance]): MeshData =
  # Independent CPU transform oracle: not the instance packer / backend path.
  for item in items:
    let c = cos(item.yaw)
    let s = sin(item.yaw)
    for v in mesh.vertices:
      var output = v
      output.position = [item.position[0]+item.scale*(c*v.position[0]+s*v.position[2]),
        item.position[1]+item.scale*v.position[1],
        item.position[2]+item.scale*(-s*v.position[0]+c*v.position[2])]
      output.normal = [c*v.normal[0]+s*v.normal[2],v.normal[1],-s*v.normal[0]+c*v.normal[2]]
      for i in 0..2: output.color[i] = v.color[i]*item.tint[i]
      result.vertices.add output

proc runInstanceProbe*(ctx: Context; caps: Capabilities; read: FrameReader) =
  var mesh: MeshData
  mesh.addBox([0'f32,0,0],[0.36'f32,0.28,0.19],[0.8'f32,0.7,0.6])
  let items = @[instance([-0.4'f32,-0.2,0.1],0.2,1,[1'f32,0.3,0.2]),
                instance([0.35'f32,0.2,-0.15],-0.65,0.7,[0.2'f32,0.4,1]),
                instance([0.1'f32,-0.32,0],1.1,1.2,[0.7'f32,1,0.2])]
  var reference = initRenderer(ctx,caps,baked(mesh,items))
  reference.render(64,64)
  let cpuImage = read()
  reference.dispose()
  for indexed in [false,true]:
    let asset = if indexed: mesh.indexed() else: mesh
    var fast = initRenderer(ctx,caps,asset,instanceCapacity=5)
    var fallback = initRenderer(ctx,caps,asset,instanceCapacity=5,forceFallback=true)
    var plain = initRenderer(ctx,caps,asset)
    doAssert fallback.instanceMode == fallbackDraws
    if caps.api in {webgl2,gles3}: doAssert fast.instanceMode == coreInstancing
    elif caps.api == webgl1 and caps.instancing: doAssert fast.instanceMode == angleInstancing
    else: doAssert fast.instanceMode == fallbackDraws
    plain.render(64,64)
    let plainImage = read()
    fast.updateInstances(items)
    fallback.updateInstances(items)
    fast.renderInstances(64,64)
    let accelerated = read()
    doAssert fast.stats.instances == 3
    doAssert fast.stats.drawCalls == (if fast.instanceMode == fallbackDraws: 3 else: 1)
    doAssert fast.stats.instanceUploadBytes == (if fast.instanceMode == fallbackDraws: 0 else: 3*InstanceBytes)
    fallback.renderInstances(64,64)
    doAssert read() == accelerated, "Hardware/fallback differ"
    doAssert fallback.stats.drawCalls == 3 and fallback.stats.instanceUploadBytes == 0
    doAssert accelerated.len == cpuImage.len
    for i in 0..<accelerated.len:
      doAssert abs(int(accelerated[i])-int(cpuImage[i])) <= 2, "CPU transform/normal oracle differs"
    # Instanced state must not leak into subsequent ordinary draws.
    plain.render(64,64)
    doAssert read() == plainImage
    let previousUpdates = fast.stats.instanceUpdates
    var rejected = false
    try: fast.updateInstances(@[instance(),instance(yaw=NaN.float32)])
    except ValueError: rejected = true
    doAssert rejected and fast.stats.instanceUpdates == previousUpdates
    rejected = false
    try: fast.updateInstances(newSeq[Instance](6))
    except ValueError: rejected = true
    doAssert rejected and fast.stats.instanceUpdates == previousUpdates
    fast.renderInstances(64,64)
    doAssert read() == accelerated
    # Count grows and shrinks without reallocation. Includes full capacity and zero.
    for count in [1,5,2,0,3]:
      var snapshot = newSeq[Instance](count)
      for i in 0..<count:
        snapshot[i] = instance([float32(i-2)*0.27'f32,0,0],float32(i)*0.3'f32,0.6)
      fast.updateInstances(snapshot)
      fallback.updateInstances(snapshot)
      fast.renderInstances(64,64)
      let frame = read()
      fallback.renderInstances(64,64)
      doAssert read() == frame
      doAssert fast.stats.instances == count and fallback.stats.drawCalls == count
      if count == 0:
        doAssert fast.stats.drawCalls == 0
        for i in 0..<frame.len: doAssert frame[i] == frame[i mod 4]
    # Seeded monkey updates include size changes, overlap, rotation, tint and empty batches.
    var seed = 568'u32
    for frameIndex in 0..<30:
      seed = seed xor (seed shl 13)
      seed = seed xor (seed shr 17)
      seed = seed xor (seed shl 5)
      let count = int(seed mod 6)
      var snapshot = newSeq[Instance](count)
      for i in 0..<count:
        let t = float32((seed shr (i mod 16)) mod 997)/997'f32
        snapshot[i] = instance([t*1.2'f32-0.6'f32,float32(i-2)*0.22'f32,t*0.4'f32-0.2'f32],
          t*6.0'f32,0.4'f32+t,tint=[t,1'f32-t,0.5'f32])
      fast.updateInstances(snapshot)
      fallback.updateInstances(snapshot)
      fast.renderInstances(64,64)
      let expected = read()
      fallback.renderInstances(64,64)
      doAssert read() == expected, "Seeded hardware/fallback mismatch"
    fast.render(64,64)
    doAssert read() == plainImage, "Static draw on instance renderer inherited a transform"
    # Composition uses the existing depth buffer: far blue cannot overwrite near red.
    fast.updateInstances(@[instance([0'f32,0,-0.5],tint=[1'f32,0,0])])
    fallback.updateInstances(@[instance([0'f32,0,0.5],tint=[0'f32,0,1])])
    fast.renderInstances(64,64)
    let nearImage = read()
    fallback.renderInstances(64,64,clear=false)
    doAssert read() == nearImage, "Overlay cleared target or lost depth"
    fast.updateInstances(newSeq[Instance]())
    fast.renderInstances(64,64,clear=false)
    doAssert read() == nearImage and fast.stats.drawCalls == 0
    fallback.renderInstances(64,64)
    doAssert read() != nearImage
    fast.stats.instanceUploadBytes = high(int)-1
    fast.stats.instanceUpdates = high(int)
    fast.updateInstances(items)
    doAssert fast.stats.instanceUpdates == high(int)
    if fast.instanceMode != fallbackDraws: doAssert fast.stats.instanceUploadBytes == high(int)
    fast.renderInstances(0,0)
    doAssert fast.stats.drawCalls == 0 and fast.stats.instances == 0
    fast.dispose()
    fast.dispose()
    rejected = false
    try: fast.updateInstances(items)
    except ValueError: rejected = true
    doAssert rejected
    # Rebuild GPU state from host-owned poses, like context restoration.
    fast = initRenderer(ctx,caps,asset,instanceCapacity=5)
    fast.updateInstances(items)
    fast.renderInstances(64,64)
    doAssert read() == accelerated
    echo "instances GPU: OK (", caps.api, ", ", fast.instanceMode, ", indexed=", indexed, ")"
    fast.dispose()
    fallback.dispose()
    plain.dispose()
