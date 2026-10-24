## Linux SDL2 GLES host. --smoke is bounded and uses readPixels ONLY as an oracle.
import std/[os, strutils]
import softgfx, softgfx/backends/gles, softgfx/hosts/sdl2
import softgfx/motion
import scene

proc run(version: int; smoke, desktopTest: bool) =
  var host = openWindow(version,if smoke or desktopTest: 320 else: 800,if smoke or desktopTest: 240 else: 600)
  var ground, cars: Renderer
  var pipeline: Pipeline
  let groundAsset = arenaMesh(version == 2,includeCars=false)
  let carAsset = carMesh(version == 2)
  let owners = arenaOwners() # retained CPU state, including edits
  var scopes: ContextScopes
  var post = defaultPost()
  if smoke:
    post.scale = 0.85
    post.exposure = 1.1
    post.vignette = 0.2
  var getError: proc(): uint32 {.cdecl.}
  var readPixels: proc(x,y,w,h: int32; format,kind:uint32; pixels:pointer) {.cdecl.}
  proc createGraphics() =
    let gl = acquire(SDL_GL_GetProcAddress)
    let caps = baseline(if version == 2: gles2 else: gles3)
    let getString = cast[proc(name: uint32): cstring {.cdecl.}](SDL_GL_GetProcAddress("glGetString"))
    getError = cast[proc(): uint32 {.cdecl.}](SDL_GL_GetProcAddress("glGetError"))
    readPixels = cast[proc(x,y,w,h: int32; format,kind:uint32; pixels:pointer) {.cdecl.}](SDL_GL_GetProcAddress("glReadPixels"))
    if getString == nil or getError == nil or readPixels == nil: raise newException(IOError,"Missing GL entry points")
    echo "SDL window GLES",version," driver: ",$getString(0x1F02)," / ",$getString(0x1F01)
    if not ($getString(0x1F02)).startsWith("OpenGL ES"):
      raise newException(IOError,"Desktop GL is not the GLES test target")
    if (smoke or desktopTest) and not ($getString(0x1F02)).startsWith("OpenGL ES " & $version & "."):
      raise newException(IOError,"Smoke test requires the requested ES major version, not a newer context")
    scopes = newContextScopes()
    ground = initRenderer(gl,caps,groundAsset,owners)
    cars = initRenderer(gl,caps,carAsset,instanceCapacity=3)
    pipeline = initPipeline(gl,caps,scopes=scopes)
  proc disposeGraphics() =
    # Even if one cleanup fails, attempt the other independent owners before close.
    try: pipeline.dispose()
    finally:
      try: cars.dispose()
      finally: ground.dispose()
  try:
    createGraphics()
    var previous, current, rendered: seq[Instance]
    previous.setLen(3); current.setLen(3); rendered.setLen(3)
    carSnapshot(0,current)
    interpolateInstances(current,current,1,previous)
    interpolateInstances(current,current,1,rendered)
    var clock = initFixedClock(stepSeconds=0.05,maxSteps=4)
    var phase, previousPhase, renderedPhase: float32
    var paused = false
    var ticks = 0
    template freezeMotion() =
      phase = renderedPhase
      previousPhase = phase
      interpolateInstances(rendered,rendered,1,previous)
      interpolateInstances(rendered,rendered,1,current)
      clock.reset()
    var angle = 0.6'f32
    var distance = 15'f32
    var last = seconds()
    let started = last
    var reported = last-1
    var frames, presented, skipped, resizes: int
    var oldWidth = 0
    var quitSeen = false
    var recreations = 0
    proc drawScene(size: SurfaceSize) =
      cars.updateInstancesIfChanged(rendered)
      if pipeline.beginFrame(size.width,size.height,post):
        try:
          let target = pipeline.renderSize()
          let matrix = arenaCamera(angle,distance).viewProjection(float32(size.width)/float32(size.height))
          ground.render(target.width,target.height,matrix,clear=false)
          cars.renderInstances(target.width,target.height,matrix,clear=false)
          pipeline.endFrame()
        finally: pipeline.cancelFrame()
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
      if input.recreate or (smoke and frames in [20,40]):
        freezeMotion()
        let logical = host.windowSize()
        let sizeBefore = host.drawableSize()
        var reference: seq[uint8]
        if smoke or desktopTest:
          # Persistent owner edits and changed camera/post state must survive too.
          ground.updateTerritory(7,5,3,5,newSeqWithOwner(15,uint8(1+recreations mod 3)))
          angle += 0.15
          drawScene(sizeBefore)
          reference.setLen(sizeBefore.width*sizeBefore.height*4)
          readPixels(0,0,int32(sizeBefore.width),int32(sizeBefore.height),0x1908,0x1401,addr reference[0])
          doAssert getError() == 0
        var retiredGround = ground
        var retiredPipeline = pipeline
        let retiredHost = host
        let retiredScopes = scopes
        disposeGraphics()
        retiredScopes.invalidate()
        host.close()
        host = openWindow(version,logical.width,logical.height)
        createGraphics() # re-resolve every entry point for the new current context
        inc recreations
        if smoke or desktopTest:
          let restoredSize = host.drawableSize()
          doAssert restoredSize == sizeBefore
          drawScene(restoredSize)
          var restored = newSeq[uint8](reference.len)
          readPixels(0,0,int32(restoredSize.width),int32(restoredSize.height),0x1908,0x1401,addr restored[0])
          doAssert getError() == 0 and restored == reference, "Recreation changed scene pixels"
          var rejected = false
          try: retiredGround.render(1,1)
          except ValueError: rejected = true
          doAssert rejected
          rejected = false
          try: discard retiredPipeline.beginFrame(1,1)
          except ValueError: rejected = true
          doAssert rejected
          rejected = false
          try: discard retiredHost.drawableSize()
          except ValueError: rejected = true
          doAssert rejected
          rejected = false
          try: retiredScopes.requireContext()
          except ValueError: rejected = true
          doAssert rejected
          echo "RECREATE PASS: generation=",recreations," pixels=",reference.len div 4
          stdout.flushFile()
        last = seconds() # creation time must not enter the simulation clock
        paused = true
      let now = seconds()
      let delta = max(0.0,now-last)
      last = now
      let size = host.drawableSize()
      let focused = host.focused()
      let minimized = host.minimized()
      if host.suspended() or (not smoke and not focused) or size.width <= 0 or size.height <= 0:
        if not paused: freezeMotion()
        paused = true
        inc skipped
        idle()
      else:
        let elapsed = if paused: 0.0 else: delta
        paused = false
        angle += float32(min(elapsed,0.1))*float32(input.orbit)
        distance = clamp(distance+float32(min(elapsed,0.1))*float32(input.zoom)*5,5'f32,30'f32)
        let plan = clock.advance(elapsed)
        if plan.paused: freezeMotion()
        for step in 0..<plan.steps:
          interpolateInstances(current,current,1,previous)
          previousPhase = phase
          phase += float32(clock.stepSeconds)
          inc ticks
          carSnapshot(phase,current)
        interpolateInstances(previous,current,plan.alpha,rendered)
        renderedPhase = previousPhase+(phase-previousPhase)*float32(plan.alpha)
        drawScene(size)
        if smoke or desktopTest:
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
      if desktopTest and now-reported >= 0.1:
        echo "HOST presents=",presented," skips=",skipped," ticks=",ticks,
          " paused=",ord(paused)," focused=",ord(focused)," minimized=",ord(minimized),
          " width=",size.width," height=",size.height," angle=",angle,
          " distance=",distance," phase=",renderedPhase," recreations=",recreations
        stdout.flushFile()
        reported = now
      if desktopTest and now-started > 60:
        raise newException(IOError,"Desktop harness did not close the window within 60 seconds")
      inc frames
      if smoke and frames > 65: raise newException(IOError,"Quit event was not consumed")
    if desktopTest:
      doAssert quitSeen and presented > 0
      echo "DESKTOP PASS: real window quit consumed"
      stdout.flushFile()
    if smoke:
      doAssert quitSeen and presented > 20 and skipped >= 2 and resizes > 5 and recreations == 2
      echo "WINDOW PASS: presents=",presented," hidden-skips=",skipped," drawable-resizes=",resizes," quit=",quitSeen
  finally:
    # GPU allocations must be deleted with their original window/context current.
    try:
      disposeGraphics()
    finally:
      host.close()
      host.close()
      if smoke or desktopTest:
        var rejected = false
        try: discard host.drawableSize()
        except ValueError: rejected = true
        doAssert rejected # closed host never reaches SDL again

let smoke = "--smoke" in commandLineParams()
let version = if "--gles2" in commandLineParams(): 2 else: 3
let desktopTest = "--desktop-test" in commandLineParams()
run(version,smoke,desktopTest)
if smoke: run(version,true,false) # SDL/window/context recreation, not only resource recreation
