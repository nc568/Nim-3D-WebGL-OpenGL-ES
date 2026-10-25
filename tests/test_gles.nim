import camera_fixture
## Real native pbuffer smoke test. Requires EGL + GLES drivers; no window required.
import softgfx, softgfx/backends/gles
import ../examples/scene
import territory_fixture, instance_fixture, post_fixture, environment_fixture, culling_fixture, motion_fixture, dirty_fixture, workload_fixture
import softgfx/timing
import softgfx/timing/gles as gpuClock
const eglLibrary {.strdefine.} = "libEGL.so.1"
{.push cdecl, dynlib: eglLibrary.}
proc eglGetDisplay(native: pointer): pointer {.importc.}
proc eglInitialize(d: pointer; major, minor: ptr int32): uint32 {.importc.}
proc eglBindAPI(api: uint32): uint32 {.importc.}
proc eglChooseConfig(d: pointer; attrs: ptr int32; config: ptr pointer; size: int32; count: ptr int32): uint32 {.importc.}
proc eglCreatePbufferSurface(d, config: pointer; attrs: ptr int32): pointer {.importc.}
proc eglCreateContext(d, config, share: pointer; attrs: ptr int32): pointer {.importc.}
proc eglMakeCurrent(d, draw, read, ctx: pointer): uint32 {.importc.}
proc eglDestroyContext(d, ctx: pointer): uint32 {.importc.}
proc eglDestroySurface(d, surface: pointer): uint32 {.importc.}
proc eglTerminate(d: pointer): uint32 {.importc.}
proc eglGetProcAddress(name: cstring): pointer {.importc.}
{.pop.}

when defined(angleSwiftShader):
  let platformDisplay = cast[proc(platform: uint32; native: pointer; attrs: ptr int32): pointer {.cdecl.}](eglGetProcAddress("eglGetPlatformDisplayEXT"))
  doAssert platformDisplay != nil
  var platformAttrs = [0x3203'i32, 0x3450, 0x3209, 0x3487, 0x348F, 0x34A5, 0x3038]
  let display = platformDisplay(0x3202, nil, addr platformAttrs[0])
else:
  let display = eglGetDisplay(nil)
doAssert display != nil
doAssert eglInitialize(display, nil, nil) != 0
doAssert eglBindAPI(0x30A0) != 0
for version in 2..3:
  var attrs = [0x3033'i32, 1, 0x3040, (if version == 2: 4 else: 64),
    0x3024, 8, 0x3023, 8, 0x3022, 8, 0x3025, 24, 0x3038]
  var config: pointer
  var count: int32
  doAssert eglChooseConfig(display, addr attrs[0], addr config, 1, addr count) != 0 and count > 0
  var size = [0x3057'i32, 64, 0x3056, 64, 0x3038]
  let surface = eglCreatePbufferSurface(display, config, addr size[0])
  var contextAttrs = [0x3098'i32, int32(version), 0x3038]
  let context = eglCreateContext(display, config, nil, addr contextAttrs[0])
  doAssert surface != nil and context != nil
  doAssert eglMakeCurrent(display, surface, surface, context) != 0
  let gl = acquire(eglGetProcAddress)
  var timer = initGpuTimer(gpuClock.timerDriver(eglGetProcAddress,proc(): bool = false))
  echo "GLES timer extension supported: ",timer.supported
  discard timer.beginSample(1)
  var renderer = initRenderer(gl, baseline(if version == 2: gles2 else: gles3), demoMesh())
  renderer.render(64, 64)
  timer.endSample()
  let readPixels = cast[proc(x,y,w,h: int32; format, kind: uint32; pixels: pointer) {.cdecl.}](eglGetProcAddress("glReadPixels"))
  let getError = cast[proc(): uint32 {.cdecl.}](eglGetProcAddress("glGetError"))
  doAssert readPixels != nil and getError != nil
  var pixel: array[4, uint8]
  readPixels(32,32,1,1,0x1908,0x1401,addr pixel[0])
  var batch: GpuBatch
  timer.poll(batch)
  if batch.count > 0:
    doAssert batch.samples[0].ms > 0
    echo "GLES timer readback samples: ",batch.count
  timer.dispose()
  doAssert pixel[0] > pixel[2] and pixel[3] == 255
  doAssert getError() == 0
  renderer.dispose()
  renderer.dispose()
  # Draw near red first, far blue last: painter order alone would produce blue.
  var occlusion: MeshData
  for z in [-0.5'f32,0.5]:
    for pos in [[-0.8'f32,-0.8,z],[0.8'f32,-0.8,z],[0'f32,0.8,z]]:
      occlusion.vertices.add Vertex(position: pos, normal: [0'f32,1,0],
        color: (if z<0: [0.8'f32,0.05,0.05] else: [0.05'f32,0.05,0.8]))
  var depthTest = initRenderer(gl, baseline(if version == 2: gles2 else: gles3), occlusion)
  depthTest.render(64,64)
  readPixels(32,32,1,1,0x1908,0x1401,addr pixel[0])
  doAssert pixel[0] > pixel[2]
  # Second frame also tests that depth was actually cleared.
  depthTest.render(64,64)
  readPixels(32,32,1,1,0x1908,0x1401,addr pixel[0])
  doAssert pixel[0] > pixel[2]
  depthTest.dispose()
  var arena = initRenderer(gl, baseline(if version == 2: gles2 else: gles3), arenaMesh(version == 2))
  var previous: array[64*64*4, uint8]
  arena.render(64,64,arenaCamera().viewProjection(1))
  readPixels(0,0,64,64,0x1908,0x1401,addr previous[0])
  var red = 0
  for i in countup(0,previous.high,4):
    if int(previous[i]) > int(previous[i+2])*13 div 10 and previous[i]>100: inc red
  doAssert red > 3
  var changed: array[64*64*4, uint8]
  arena.render(64,64,arenaCamera(2.0,12).viewProjection(1))
  readPixels(0,0,64,64,0x1908,0x1401,addr changed[0])
  doAssert changed != previous
  arena.render(64,64,arenaCamera().viewProjection(1))
  readPixels(0,0,64,64,0x1908,0x1401,addr changed[0])
  doAssert changed == previous
  doAssert getError() == 0
  arena.dispose()
  runTerritoryProbe(gl,baseline(if version == 2: gles2 else: gles3),proc(x,y: int): array[4,uint8] =
    readPixels(int32(x),int32(y),1,1,0x1908,0x1401,addr result[0]))
  doAssert getError() == 0
  var ground = initRenderer(gl,baseline(if version == 2: gles2 else: gles3),
    arenaMesh(version == 2,includeCars=false),arenaOwners())
  var cars = initRenderer(gl,baseline(if version == 2: gles2 else: gles3),
    carMesh(version == 2),instanceCapacity=3)
  var poses = newSeq[Instance](3)
  for tick in 0..2:
    carSnapshot(float32(tick),poses)
    cars.updateInstances(poses)
    let matrix = arenaCamera().viewProjection(1)
    ground.render(64,64,matrix)
    cars.renderInstances(64,64,matrix,clear=false)
    doAssert ground.stats.drawCalls+cars.stats.drawCalls == (if version == 2: 4 else: 2)
    readPixels(0,0,64,64,0x1908,0x1401,addr changed[0])
    if tick > 0: doAssert changed != previous
    previous = changed
  doAssert getError() == 0
  ground.dispose()
  cars.dispose()
  runInstanceProbe(gl,baseline(if version == 2: gles2 else: gles3),proc(): seq[uint8] =
    result = newSeq[uint8](64*64*4)
    readPixels(0,0,64,64,0x1908,0x1401,addr result[0]))
  doAssert getError() == 0
  runPostProbe(gl,baseline(if version == 2: gles2 else: gles3),proc(): seq[uint8] =
    result = newSeq[uint8](64*64*4)
    readPixels(0,0,64,64,0x1908,0x1401,addr result[0]))
  doAssert getError() == 0
  runEnvironmentProbe(gl,baseline(if version == 2: gles2 else: gles3),proc(): seq[uint8] =
    result = newSeq[uint8](64*64*4)
    readPixels(0,0,64,64,0x1908,0x1401,addr result[0]))
  doAssert getError() == 0
  runCullingProbe(gl,baseline(if version == 2: gles2 else: gles3),proc(): seq[uint8] =
    result = newSeq[uint8](64*64*4)
    readPixels(0,0,64,64,0x1908,0x1401,addr result[0]))
  doAssert getError() == 0
  runMotionProbe(gl,baseline(if version == 2: gles2 else: gles3),proc(): seq[uint8] =
    result = newSeq[uint8](64*64*4)
    readPixels(0,0,64,64,0x1908,0x1401,addr result[0]))
  doAssert getError() == 0
  runDirtyProbe(gl,baseline(if version == 2: gles2 else: gles3),proc(): seq[uint8] =
    result = newSeq[uint8](64*64*4)
    readPixels(0,0,64,64,0x1908,0x1401,addr result[0]))
  doAssert getError() == 0
  runCameraProbe(gl,baseline(if version == 2: gles2 else: gles3),proc(): seq[uint8] =
    result = newSeq[uint8](64*64*4)
    readPixels(0,0,64,64,0x1908,0x1401,addr result[0]))
  doAssert getError() == 0
  runWorkloadProbe(gl,baseline(if version == 2: gles2 else: gles3),proc(): seq[uint8] =
    result = newSeq[uint8](64*64*4)
    readPixels(0,0,64,64,0x1908,0x1401,addr result[0]))
  doAssert getError() == 0
  doAssert eglMakeCurrent(display, nil, nil, nil) != 0
  doAssert eglDestroyContext(display, context) != 0
  doAssert eglDestroySurface(display, surface) != 0
  echo "GLES ", version, ": OK"
doAssert eglTerminate(display) != 0
