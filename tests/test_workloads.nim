## Repeatable CPU cost experiment. Times are observations, NEVER pass thresholds.
import std/[json, math]
import softgfx/[instances, culling, math3d]
when defined(js):
  proc milliseconds(): float64 {.importjs: "performance.now()".}
  const compiler = "js"
else:
  import std/[monotimes, times]
  proc milliseconds(): float64 = float64(getMonoTime().ticks)/1_000_000.0
  const compiler = when defined(nimCproc): "qbe" elif defined(clang): "llvm" else: "gcc"
const iterations = 12
const buildMode = when defined(release): "release" else: "debug"
for count in [64,1024,8192]:
  var items = newSeq[Instance](count)
  let side = if count == 64: 8 else: 32
  for i in 0..<count:
    items[i] = instance([float32(i mod side)*2-float32(side-1), float32(i div (side*side))*2,
      float32((i div side) mod side)*2-float32(side-1)],yaw=float32(i mod 19)*0.1)
  var packed = newSeq[float32](count*InstanceFloats)
  packInstances(items,packed)
  var skipped = 0
  let packStart = milliseconds()
  for repeat in 0..<iterations:
    if not packInstancesChanged(items,packed): inc skipped
  let unchangedMs = milliseconds()-packStart
  doAssert skipped == iterations
  let forcedStart = milliseconds()
  for repeat in 0..<iterations: packInstances(items,packed)
  let forcedMs = milliseconds()-forcedStart
  let movingStart = milliseconds()
  for repeat in 0..<iterations:
    for i in 0..<count: items[i].position[0] += 0.01
    doAssert packInstancesChanged(items,packed)
  let movingMs = milliseconds()-movingStart
  let local = Bounds(lower:[-0.2,-0.2,-0.2],upper:[0.2,0.2,0.2])
  var grid = initSpatialGrid(Bounds(lower:[-32.0,-2.0,-32.0],upper:[32.0,18.0,32.0]),[16,4,16],count)
  var flat, selected: seq[int]
  flat.setLen(count); selected.setLen(count)
  var stats: GridQueryStats
  let rebuildStart = milliseconds()
  for repeat in 0..<iterations: grid.rebuild(local,items)
  let rebuildMs = milliseconds()-rebuildStart
  for dense in [false,true]:
    var matrix = identity()
    if dense:
      matrix[0] = 0.02
      matrix[5] = 0.02
      matrix[10] = 0.02
    let view = frustum(matrix)
    let flatStart = milliseconds()
    var expected = 0
    for repeat in 0..<iterations: expected = view.collectVisible(local,items,flat)
    let flatMs = milliseconds()-flatStart
    let gridStart = milliseconds()
    for repeat in 0..<iterations:
      let actual = view.collectVisible(grid,selected,stats)
      doAssert actual == expected
    let gridMs = milliseconds()-gridStart
    for i in 0..<expected: doAssert selected[i] == flat[i]
    doAssert stats.cellVisits == stats.occupiedCells and stats.cellVisits <= count
    if dense:
      doAssert expected == count and stats.orderScans == count and stats.orderComparisons == 0
    else:
      doAssert stats.orderScans == 0 and stats.instanceTests < count div 2
    var record = %*{"compiler":compiler,"buildMode":buildMode,"instances":count,"iterations":iterations,
      "dense":dense,"visible":expected,"instanceTests":stats.instanceTests,
      "cellVisits":stats.cellVisits,"occupiedCells":stats.occupiedCells,"orderScans":stats.orderScans,"orderComparisons":stats.orderComparisons,
      "unchangedSkipped":skipped,"unchangedPackMs":unchangedMs,"forcedPackMs":forcedMs,
      "movingPackMs":movingMs,"rebuildMs":rebuildMs,"flatQueryMs":flatMs,"gridQueryMs":gridMs}
    echo "CPU_WORKLOAD ",$record
    # Exercise sparse after dense, so stale marks cannot contaminate later queries.
    let sparse = frustum(identity())
    let n = sparse.collectVisible(local,items,flat)
    doAssert sparse.collectVisible(grid,selected,stats) == n
    for i in 0..<n: doAssert selected[i] == flat[i]
echo "CPU workloads exact prefix / adaptive ordering / changed packing PASS"
