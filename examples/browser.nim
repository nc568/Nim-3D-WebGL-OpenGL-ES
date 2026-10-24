import std/[jsffi, math]
import softgfx, softgfx/backends/web, scene
import softgfx/[timing, profiling, autoscale, culling, motion]
import softgfx/timing/web as gpuClock
proc canvas(): JsObject {.importjs: "document.getElementById('scene')".}
proc legacy(): bool {.importjs: "(new URLSearchParams(location.search).has('webgl1'))".}
proc markReady(api: cstring) {.importjs: "(document.getElementById('status').textContent = #)".}
proc publish(callback: proc()) {.importjs: "(globalThis.softgfxRender = #)".}
proc onEvent(target: JsObject; name: cstring; cb: proc(e: JsObject)) {.importjs: "#.addEventListener(#, #)".}
let surface = canvas()
let device = acquire(surface, legacy())
proc fallback(): bool {.importjs: "(new URLSearchParams(location.search).has('fallback'))".}
proc showMode(mode: cstring) {.importjs: "(document.getElementById('batch-mode').textContent = #)".}
proc showStats(draws: int) {.importjs: "(document.getElementById('batch-stats').textContent = # + ' draw calls / кадр')".}
let asset = arenaMesh(device.caps.api == webgl1, includeCars=false)
let carAsset = carMesh(device.caps.api == webgl1)
let carBounds = carAsset.meshBounds()
var visibleIndices = newSeq[int](3)
var cullingEnabled = false
var poses = newSeq[Instance](3)
var simulationTime = 0'f32
carSnapshot(simulationTime,poses)
var previousPoses = newSeq[Instance](3)
var currentPoses = newSeq[Instance](3)
var fixedClock = initFixedClock(stepSeconds=0.05,maxSteps=4)
var previousTime, renderedTime = 0'f32
var renderAlpha, droppedSimulationSeconds, lastMs: float64
var simulationTicks = 0
proc resetMotionHistory() =
  interpolateInstances(poses,poses,1,previousPoses)
  interpolateInstances(poses,poses,1,currentPoses)
  previousTime = simulationTime
  renderedTime = simulationTime
  renderAlpha = 0
  fixedClock.reset()
resetMotionHistory()
let owners = arenaOwners()
var renderer = initRenderer(device.ctx, device.caps, asset, owners)
var cars = initRenderer(device.ctx,device.caps,carAsset,instanceCapacity=3,forceFallback=fallback())
cars.updateInstances(poses)
showMode(cstring($cars.instanceMode))
const SkyBottom = [0.42'f32,0.51,0.62]
const SkyTop = [0.12'f32,0.24,0.42]
var sky = initSkyRenderer(device.ctx,device.caps,SkyBottom,SkyTop)
var skyEnabled = true
var fogEnabled = true
var shadowsEnabled = true
var atmosphere = SceneEffects(fogEnabled:true,fogNear:18,fogFar:55,fogColor:SkyBottom)
for i in 0..2:
  atmosphere.blobs[i] = BlobShadow(radiusX:0.95,radiusZ:1.6,strength:0.45)
var pipeline = initPipeline(device.ctx,device.caps)
var post = defaultPost()
proc showPost(w,h,draws: int) {.importjs: "(document.getElementById('post-stats').textContent = # + '×' + # + ' · final: ' + #)".}
proc clockMs(): float64 {.importjs: "performance.now()".}
proc visible(): bool {.importjs: "(document.visibilityState === 'visible')".}
proc publishTiming(cb: proc(): JsObject) {.importjs: "(globalThis.softgfxTiming = #)".}
proc timingText(text: cstring) {.importjs: "(document.getElementById('timing-stats').textContent = #)".}
var timer = initGpuTimer(gpuClock.timerDriver(device.ctx,device.caps.api == webgl2))
var profile = initFrameProfile()
var readback: GpuBatch
var automatic = false
var scaler = initAutoScale()
proc autoActive(): bool = automatic and timer.supported and post.enabled and device.caps.api == webgl2
proc autoUnavailable(value: bool) {.importjs: "(document.getElementById('auto-scale').disabled = #)".}
proc updateScaleControl(value: float32) {.importjs: "(document.getElementById('post-scale').value = #)".}
var measuring = false
var running = false
var measuredWidth, measuredHeight, seenInvalidations: int
proc resetMeasurements(settling = false) =
  timer.reset()
  profile = initFrameProfile()
  scaler.reset(post.scale,settling)
  seenInvalidations = timer.invalidations
proc timingReport(): JsObject =
  let report = profile.report()
  result = newJsObject()
  result.autoRequested = automatic
  result.autoActive = autoActive()
  result.scaleChanges = scaler.changes
  result.frames = report.frames
  result.warmupFrames = report.warmupFrames
  result.cpuSamples = report.cpu.samples
  result.gpuSamples = report.gpu.samples
  result.gpuSupported = timer.supported
  result.skipped = timer.skipped
  result.invalidations = timer.invalidations
  result.cpuMedianMs = nil
  result.cpuP95Ms = nil
  result.gpuMedianMs = nil
  result.gpuP95Ms = nil
  if report.cpu.samples > 0:
    result.cpuMedianMs = report.cpu.medianMs
    result.cpuP95Ms = report.cpu.p95Ms
  if report.gpu.samples > 0:
    result.gpuMedianMs = report.gpu.medianMs
    result.gpuP95Ms = report.gpu.p95Ms
  result.renderWidth = pipeline.stats.renderWidth
  result.renderHeight = pipeline.stats.renderHeight
  result.drawCalls = renderer.stats.drawCalls+cars.stats.drawCalls+pipeline.stats.finalDrawCalls+(if skyEnabled: sky.stats.drawCalls else: 0)
  result.api = cstring($device.caps.api)
  result.scale = post.scale
  result.simulationStepSeconds = fixedClock.stepSeconds
  result.simulationTicks = simulationTicks
  result.renderAlpha = renderAlpha
  result.droppedSimulationSeconds = droppedSimulationSeconds
  result.cullingEnabled = cullingEnabled
  result.visibleCars = cars.stats.instances
  result.sourceCars = poses.len
  result.skyEnabled = skyEnabled
  result.fogEnabled = fogEnabled
  result.shadowsEnabled = shadowsEnabled
  result.animated = running
  result.fxaa = post.fxaa
  result.postEnabled = post.enabled
  result.instanceMode = cstring($cars.instanceMode)
  result.targetBytes = pipeline.stats.allocatedBytes
publishTiming(timingReport)
proc refreshTiming() =
  let report = profile.report()
  let gpu = if not timer.supported: "GPU: unavailable"
            elif report.gpu.samples == 0: "GPU: warmup/pending"
            else: "GPU median/p95: " & $report.gpu.medianMs & "/" & $report.gpu.p95Ms & " ms"
  let cpu = if report.cpu.samples == 0: "CPU submit: no samples"
            else: "CPU submit median/p95: " & $report.cpu.medianMs & "/" & $report.cpu.p95Ms & " ms"
  timingText(cstring(cpu & " · " & gpu & " · frames: " & $report.frames))
var angle = 0.6
var distance = 15.0
var lost = false
proc drawFrame() =
  if not lost:
    let w = surface.width.to(int)
    let h = surface.height.to(int)
    if w > 0 and h > 0:
      var frame = 0
      var started = 0.0
      if (measuring or autoActive()) and visible():
        if measuredWidth != w or measuredHeight != h:
          resetMeasurements()
          measuredWidth = w
          measuredHeight = h
        timer.poll(readback)
        if seenInvalidations != timer.invalidations:
          resetMeasurements()
          readback.count = 0
        frame = profile.nextFrame()
        let now = clockMs()
        scaler.submitted(frame,now)
        for i in 0..<readback.count:
          profile.recordGpu(readback.samples[i])
          if autoActive() and scaler.observe(readback.samples[i],now):
            post.scale = scaler.scale
            updateScaleControl(post.scale)
            resetMeasurements(settling=true)
            frame = profile.nextFrame()
            scaler.submitted(frame,now)
            break # remaining readbacks describe the OLD resolution

        started = clockMs()
        if timer.supported: discard timer.beginSample(frame)
      try:
        let camera = arenaCamera(float32(angle),float32(distance))
        let matrix = camera.viewProjection(float32(w)/float32(h))
        if cullingEnabled:
          let count = frustum(matrix).collectVisible(carBounds,poses,visibleIndices)
          cars.updateVisibleInstances(poses,visibleIndices,count)
        # Keep ALL caster poses below: an offscreen car can cast a visible shadow.
        atmosphere.fogEnabled = fogEnabled
        atmosphere.eye = camera.eye
        atmosphere.blobCount = if shadowsEnabled: 3 else: 0
        for i in 0..2:
          atmosphere.blobs[i].center[0] = poses[i].position[0]
          atmosphere.blobs[i].center[1] = -0.02
          atmosphere.blobs[i].center[2] = poses[i].position[2]
          atmosphere.blobs[i].yaw = poses[i].yaw
        renderer.updateEffects(atmosphere)
        atmosphere.blobCount = 0 # cars are casters, not horizontal receivers
        cars.updateEffects(atmosphere)
        if pipeline.beginFrame(w,h,post):
          let size = pipeline.renderSize()
          if skyEnabled: sky.renderBackground(size.width,size.height)
          renderer.render(size.width,size.height,matrix,clear=false)
          cars.renderInstances(size.width,size.height,matrix,clear=false)
          pipeline.endFrame()
      except:
        timer.reset()
        profile.resetGpu()
        raise
      finally:
        pipeline.cancelFrame()
        if frame > 0: timer.endSample()
      if frame > 0:
        profile.recordCpu(frame,clockMs()-started)
        if frame mod 30 == 0: refreshTiming()
      showStats(renderer.stats.drawCalls+cars.stats.drawCalls+pipeline.stats.finalDrawCalls+(if skyEnabled: sky.stats.drawCalls else: 0))
      showPost(pipeline.stats.renderWidth,pipeline.stats.renderHeight,pipeline.stats.finalDrawCalls)
publish(drawFrame)
onEvent(surface, "webglcontextlost", proc(e: JsObject) =
  e.preventDefault()
  lost = true
  lastMs = 0
  pipeline.abandon()
  timer.abandon()
  profile = initFrameProfile()
  refreshTiming()
  markReady("lost"))
onEvent(surface, "webglcontextrestored", proc(e: JsObject) =
  # All previous GL resources are invalid. Rebuild from retained CPU asset.
  pipeline = initPipeline(device.ctx,device.caps)
  timer = initGpuTimer(gpuClock.timerDriver(device.ctx,device.caps.api == webgl2))
  resetMeasurements()
  autoUnavailable(device.caps.api == webgl1 or not timer.supported)
  sky = initSkyRenderer(device.ctx,device.caps,SkyBottom,SkyTop)
  renderer = initRenderer(device.ctx, device.caps, asset, owners)
  cars = initRenderer(device.ctx,device.caps,carAsset,instanceCapacity=3,forceFallback=fallback())
  cars.updateInstances(poses)
  showMode(cstring($cars.instanceMode))
  lost = false
  drawFrame()
  refreshTiming()
  markReady(cstring($device.caps.api)))
drawFrame()
markReady(cstring($device.caps.api))

# Input belongs to the host example, not the graphics library.
var dragging = false
var lastX = 0.0
onEvent(surface, "pointerdown", proc(e: JsObject) =
  dragging = true
  lastX = e.clientX.to(float)
  surface.setPointerCapture(e.pointerId))
onEvent(surface, "pointermove", proc(e: JsObject) =
  if dragging:
    let x = e.clientX.to(float)
    angle = (angle + (x-lastX)*0.008) mod (2*PI)
    lastX = x
    drawFrame())
onEvent(surface, "pointerup", proc(e: JsObject) = dragging = false)
onEvent(surface, "pointercancel", proc(e: JsObject) = dragging = false)
onEvent(surface, "lostpointercapture", proc(e: JsObject) = dragging = false)
onEvent(surface, "wheel", proc(e: JsObject) =
  e.preventDefault()
  distance = clamp(distance + e.deltaY.to(float)*0.015, 7.0, 32.0)
  drawFrame())

proc button(): JsObject {.importjs: "document.getElementById('paint-territory')".}
var owner: uint8 = 0
onEvent(button(), "click", proc(e: JsObject) =
  owner = uint8(int(owner) mod 3 + 1)
  let data = newSeqWithOwner(15,owner)
  if lost: owners.applyDelta(7,5,3,5,data)
  else: renderer.updateTerritory(7,5,3,5,data)
  drawFrame())

proc element(id: cstring): JsObject {.importjs: "document.getElementById(#)".}
proc requestFrame(cb: proc(ms: float)) {.importjs: "requestAnimationFrame(#)".}
proc advance(seconds: float32) =
  simulationTime = (simulationTime+seconds) mod (2*PI.float32/0.6'f32)
  carSnapshot(simulationTime,poses)
  resetMotionHistory()
  if not lost:
    if not cullingEnabled: cars.updateInstances(poses)
    drawFrame()
onEvent(element("step-cars"),"click",proc(e: JsObject) = advance(0.25))
onEvent(element("run-cars"),"click",proc(e: JsObject) =
  running = not running
  lastMs = 0
  element("run-cars").textContent = (if running: cstring("Пауза") else: cstring("▶ Ехать")))
proc advanceRendered(seconds: float64) =
  let plan = fixedClock.advance(seconds)
  droppedSimulationSeconds += plan.droppedSeconds
  if plan.paused:
    # Demo policy: freeze the displayed phase, never fast-forward on a stall.
    # An authoritative game should choose its own suspend/reset policy instead.
    simulationTime = renderedTime
    resetMotionHistory()
  else:
    for tick in 0..<plan.steps:
      interpolateInstances(currentPoses,currentPoses,1,previousPoses)
      previousTime = simulationTime
      simulationTime = (simulationTime+float32(fixedClock.stepSeconds)) mod (2*PI.float32/0.6'f32)
      carSnapshot(simulationTime,currentPoses)
      if simulationTicks < high(int): inc simulationTicks
    renderAlpha = plan.alpha
    interpolateInstances(previousPoses,currentPoses,renderAlpha,poses)
    # Handle analytic demo phase wrap without interpolating backward in time.
    var span = simulationTime-previousTime
    if span < 0: span += 2*PI.float32/0.6'f32
    renderedTime = (previousTime+span*float32(renderAlpha)) mod (2*PI.float32/0.6'f32)
  if not lost:
    if not cullingEnabled: cars.updateInstances(poses)
    drawFrame()
proc publishAdvance(cb: proc(seconds: float64)) {.importjs: "(globalThis.softgfxAdvance = #)".}
publishAdvance(advanceRendered) # example/test hook, not a graphics-library global
proc animate(ms: float) =
  if running and not lost and visible():
    if lastMs > 0: advanceRendered(max(0.0,(ms-lastMs)/1000))
    lastMs = ms
  else:
    lastMs = 0
    if (measuring or autoActive()) and not lost and visible(): drawFrame()
  requestFrame(animate)
requestFrame(animate)

# Manual settings reset the GPU evidence; automatic control is opt-in.
for id in ["post-enabled", "post-fxaa", "post-dither", "post-scale"]:
  if device.caps.api == webgl1: element(cstring(id)).disabled = true
  onEvent(element(cstring(id)),"input",proc(e: JsObject) =
    post.enabled = element("post-enabled").checked.to(bool)
    post.fxaa = element("post-fxaa").checked.to(bool)
    post.dither = element("post-dither").checked.to(bool)
    post.scale = element("post-scale").valueAsNumber.to(float32)
    resetMeasurements()
    drawFrame())

onEvent(element("measure-timing"),"click",proc(e: JsObject) =
  measuring = not measuring
  if measuring: resetMeasurements()
  elif autoActive(): resetMeasurements()
  else: timer.reset()
  element("measure-timing").textContent = (if measuring: cstring("Стоп измерения") else: cstring("Измерить CPU/GPU"))
  refreshTiming())
proc documentObject(): JsObject {.importjs: "(document)".}
onEvent(documentObject(),"visibilitychange",proc(e: JsObject) =
  resetMeasurements()
  refreshTiming()
  lastMs = 0)

autoUnavailable(device.caps.api == webgl1 or not timer.supported)
onEvent(element("auto-scale"),"input",proc(e: JsObject) =
  automatic = element("auto-scale").checked.to(bool)
  resetMeasurements()
  refreshTiming())

for id in ["env-sky","env-fog","env-shadows"]:
  onEvent(element(cstring(id)),"input",proc(e: JsObject) =
    skyEnabled = element("env-sky").checked.to(bool)
    fogEnabled = element("env-fog").checked.to(bool)
    shadowsEnabled = element("env-shadows").checked.to(bool)
    resetMeasurements()
    drawFrame())

onEvent(element("cull-cars"),"input",proc(e: JsObject) =
  cullingEnabled = element("cull-cars").checked.to(bool)
  if not lost and not cullingEnabled: cars.updateInstances(poses)
  resetMeasurements()
  drawFrame())
