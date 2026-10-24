## Controlled CPU-only release benchmark; browser engines execute identical JS.
import std/[json, algorithm]
import softgfx/[instances, culling, math3d]
when not defined(release): {.error: "Benchmark requires -d:release".}
when defined(js):
  proc clock(): float64 {.importjs: "performance.now()".}
else:
  import std/[monotimes, times]
  proc clock(): float64 = float64(getMonoTime().ticks)/1_000_000.0
const warmup = 20
const samples = 41
proc require(ok: bool) =
  # Do not rely on assertion build flags for benchmark correctness.
  if not ok: raise newException(ValueError,"Release workload oracle failed")
proc summary(values: seq[float64]): JsonNode =
  var sorted = values
  sorted.sort()
  %*{"samples":samples,"medianMs":sorted[samples div 2],
    "p95Ms":sorted[38],"minMs":sorted[0],"rawMs":values}
proc benchmark(count: int; moving, dense: bool): string =
  if count notin [64,1024,8192]: raise newException(ValueError,"Unsupported workload size")
  var items = newSeq[Instance](count)
  let side = if count == 64: 8 else: 32
  for i in 0..<count:
    items[i] = instance([float32(i mod side)*2-float32(side-1),
      float32(i div (side*side))*2,float32((i div side) mod side)*2-float32(side-1)])
  let bounds = Bounds(lower:[-0.3,-0.3,-0.3],upper:[0.3,0.3,0.3])
  var grid = initSpatialGrid(Bounds(lower:[-32.0,-2.0,-32.0],upper:[32.0,18.0,32.0]),[16,4,16],count)
  var matrix = identity()
  if dense:
    matrix[0] = 0.02; matrix[5] = 0.02; matrix[10] = 0.02
  let view = frustum(matrix)
  var flat = newSeq[int](count)
  var selected = newSeq[int](count)
  var packed = newInstanceData(count)
  var forced = newInstanceData(count)
  var stats: GridQueryStats
  var span: InstanceRange
  var packing, forcing, rebuilding, flatQuery, gridQuery: seq[float64]
  packing.setLen(samples); forcing.setLen(samples); rebuilding.setLen(samples)
  flatQuery.setLen(samples); gridQuery.setLen(samples)
  packInstances(items,packed)
  grid.rebuild(bounds,items)
  var visible, changedRecords, skipped: int
  for step in 0..<warmup+samples:
    if moving:
      # Alternate a deterministic pose offset; mutation itself is OUTSIDE timings.
      for i in 0..<count: items[i].position[0] += (if step mod 2 == 0: 0.02'f32 else: -0.02'f32)
    var start = clock()
    packInstancesRange(items,packed,span)
    let packMs = clock()-start
    start = clock()
    packInstances(items,forced)
    let forcedMs = clock()-start
    require(packed == forced)
    let changed = max(0,span.last-span.first)
    require(changed == (if moving: count else: 0))
    start = clock()
    if moving: grid.rebuild(bounds,items)
    let rebuildMs = clock()-start
    start = clock()
    visible = view.collectVisible(bounds,items,flat)
    let flatMs = clock()-start
    start = clock()
    let actual = view.collectVisible(grid,selected,stats)
    let queryMs = clock()-start
    require(actual == visible)
    for i in 0..<visible: require(flat[i] == selected[i])
    if dense: require(visible == count)
    if step >= warmup:
      let index = step-warmup
      packing[index] = packMs; forcing[index] = forcedMs
      rebuilding[index] = if moving: rebuildMs else: 0
      flatQuery[index] = flatMs; gridQuery[index] = queryMs
      changedRecords += changed
      if changed == 0: inc skipped
  result = $(%*{"schemaVersion":1,"buildMode":"release","scope":"CPU only; not FPS",
    "instances":count,"moving":moving,"dense":dense,"warmup":warmup,"samples":samples,
    "visible":visible,"changedRecords":changedRecords,"skipped":skipped,
    "instanceTests":stats.instanceTests,"orderScans":stats.orderScans,
    "packing":summary(packing),"forcedPacking":summary(forcing),"rebuild":summary(rebuilding),
    "flatQuery":summary(flatQuery),"gridQuery":summary(gridQuery)})
when defined(js):
  proc publish(cb: proc(count: int; moving,dense: bool): cstring) {.importjs: "(globalThis.softgfxBench = #)".}
  proc browserBench(count: int; moving,dense: bool): cstring = cstring(benchmark(count,moving,dense))
  publish(browserBench)
else:
  for count in [64,1024,8192]:
    for moving in [false,true]:
      for dense in [false,true]: echo benchmark(count,moving,dense)
