## Linux SDL2 GLES host. --smoke is bounded and uses readPixels ONLY as an oracle.
import std/[os, strutils]
import softgfx, softgfx/backends/gles, softgfx/hosts/sdl2
import softgfx/motion
import scene

proc run(version: int; smoke: bool) =
  let host = openWindow(version,if smoke: 320 else: 800,if smoke: 240 else: 600)
  var ground, cars: Renderer
  var pipeline: Pipeline
  try:
    let gl = acquire(SDL_GL_GetProcAddress)
    let caps = baseline(if version == 2: gles2 else: gles3)
    let getString = cast[proc(name: uint32): cstring {.cdecl.}](SDL_GL_GetProcAddress("glGetString"))
    let getError = cast[proc(): uint32 {.cdecl.}](SDL_GL_GetProcAddress("glGetError"))
    let readPixels = cast[proc(x,y,w,h: int32; format,kind:uint32; pixels:pointer) {.cdecl.}](SDL_GL_GetProcAddress("glReadPixels"))
    if getString == nil or getError == nil or readPixels == nil: raise newException(IOError,"Missing GL entry points")
    echo "SDL window GLES",version," driver: ",$getString(0x1F02)," / ",$getString(0x1F01)
    if not ($getString(0x1F02)).startsWith("OpenGL ES"):
      raise newException(IOError,"Desktop GL is not the GLES test target")
    ground = initRenderer(gl,caps,arenaMesh(version == 2,includeCars=false),arenaOwners())
    cars = initRenderer(gl,caps,carMesh(version == 2),instanceCapacity=3)
    pipeline = initPipeline(gl,caps,scopes=newContextScopes())
    var previous, current, rendered: seq[Instance]
    previous.setLen(3); current.setLen(3); rendered.setLen(3)
    carSnapshot(0,current)
    interpolateInstances(current,current,1,previous)
    var clock = initFixedClock(stepSeconds=0.05,maxSteps=4)
    var phase = 0'f32
    var angle = 0.6'f32
    var distance = 15'f32
    var last = seconds()
    var frames, presented, skipped, resizes: int
    var oldWidth = 0
    var quitSeen = false
    var pixels: seq[uint8] # test readback allocation, never interactive hot path
    while true:
      if smoke:
        if frames == 5: host.setHidden(true)
        if frames == 7: host.setHidden(false)
        if frames >= 10 and frames < 50 and frames mod 2 == 0:
          host.resize(160+(frames*37 mod 200),120+(frames*23 mod 160))
        if frames == 60: host.requestQuit()
      let input = host.poll()
      if input.quit:
        quitSeen = true
        break
      let now = seconds()
      let delta = max(0.0,now-last)
      last = now
      let size = host.drawableSize()
      if host.suspended() or size.width <= 0 or size.height <= 0:
        clock.reset()
        inc skipped
        idle()
      else:
        angle += float32(min(delta,0.1))*float32(input.orbit)
        distance = clamp(distance+float32(min(delta,0.1))*float32(input.zoom)*5,5'f32,30'f32)
        let plan = clock.advance(delta)
        for step in 0..<plan.steps:
          interpolateInstances(current,current,1,previous)
          phase += float32(clock.stepSeconds)
          carSnapshot(phase,current)
        interpolateInstances(previous,current,plan.alpha,rendered)
        cars.updateInstancesIfChanged(rendered)
        if pipeline.beginFrame(size.width,size.height):
          try:
            let target = pipeline.renderSize()
            let matrix = arenaCamera(angle,distance).viewProjection(float32(size.width)/float32(size.height))
            ground.render(target.width,target.height,matrix,clear=false)
            cars.renderInstances(target.width,target.height,matrix,clear=false)
            pipeline.endFrame()
          finally: pipeline.cancelFrame()
        if smoke:
          doAssert getError() == 0
          if oldWidth != size.width:
            inc resizes
            oldWidth = size.width
          if frames == 0 or frames == 50:
            pixels.setLen(size.width*size.height*4)
            readPixels(0,0,int32(size.width),int32(size.height),0x1908,0x1401,addr pixels[0])
            var different = 0
            for i in countup(0,pixels.len-4,4):
              if pixels[i] != pixels[0] or pixels[i+1] != pixels[1] or pixels[i+2] != pixels[2]: inc different
            doAssert different > size.width*size.height div 20, "Window frame is blank"
            doAssert getError() == 0
        host.swap()
        inc presented
      inc frames
      if smoke and frames > 65: raise newException(IOError,"Quit event was not consumed")
    if smoke:
      doAssert quitSeen and presented > 20 and skipped >= 2 and resizes > 5
      echo "WINDOW PASS: presents=",presented," hidden-skips=",skipped," drawable-resizes=",resizes," quit=",quitSeen
  finally:
    # GPU allocations must be deleted with their original window/context current.
    try:
      pipeline.dispose()
      cars.dispose()
      ground.dispose()
    finally:
      host.close()
      host.close()

let smoke = "--smoke" in commandLineParams()
let version = if "--gles2" in commandLineParams(): 2 else: 3
run(version,smoke)
if smoke: run(version,true) # SDL/window/context recreation, not only resource recreation
