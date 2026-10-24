## GPU workload/counter oracles; software pixels/call budgets, not hardware FPS.
import std/json
import softgfx, softgfx/[geometry, culling]
import instance_fixture
when defined(js):
  proc trackRanges(gl: Context) {.importjs: """(function(g){const b=g.bufferSubData;g._ranges=[];g._restoreRanges=()=>{g.bufferSubData=b;};g.bufferSubData=function(t,o,d){g._ranges.push([o,d.byteLength]);return b.call(g,t,o,d);};})(#)""".}
  proc checkRange(gl: Context; offset, size: int): bool {.importjs: "(function(g,o,s){return g._ranges.length===1 && g._ranges[0][0]===o && g._ranges[0][1]===s;})(#,#,#)".}
  proc untrackRanges(gl: Context) {.importjs: "#._restoreRanges()".}
proc runWorkloadProbe*(ctx: Context; caps: Capabilities; read: FrameReader) =
  const count = 256
  const compiler = when defined(js): "js" elif defined(nimCproc): "qbe" elif defined(clang): "llvm" else: "gcc"
  const buildMode = when defined(release): "release" else: "debug"
  var mesh: MeshData
  mesh.addBox([0'f32,0,0],[0.08'f32,0.08,0.08],[0.8'f32,0.3,0.2])
  mesh = mesh.indexed()
  let bounds = mesh.meshBounds()
  var items = newSeq[Instance](count)
  var grid = initSpatialGrid(Bounds(lower:[-3.0,-3.0,-1.0],upper:[3.0,3.0,1.0]),[8,8,1],count)
  var indices, oracle: seq[int]
  indices.setLen(count); oracle.setLen(count)
  var stats: GridQueryStats
  for fallback in [false,true]:
    for i in 0..<count:
      items[i] = instance([float32(i mod 16)*0.3'f32-2.25'f32,float32(i div 16)*0.3'f32-2.25'f32,0],yaw=float32(i)*0.1'f32)

    var reference = initRenderer(ctx,caps,mesh,instanceCapacity=count,forceFallback=fallback,unlit=true)
    var optimized = initRenderer(ctx,caps,mesh,instanceCapacity=count,forceFallback=fallback,unlit=true)
    try:
      reference.updateInstances(items)
      doAssert optimized.updateInstancesIfChanged(items)
      reference.renderInstances(64,64)
      let initial = read()
      optimized.renderInstances(64,64)
      doAssert read() == initial
      let before = optimized.stats.instanceUploadBytes
      for repeat in 0..<32:
        reference.updateInstances(items)
        doAssert not optimized.updateInstancesIfChanged(items)
      doAssert optimized.stats.instanceUpdates == 1 and optimized.stats.instanceSkippedUpdates == 32
      doAssert optimized.stats.instanceUploadBytes == before
      doAssert reference.stats.instanceUpdates == 33
      let saved = reference.stats.instanceUploadBytes-optimized.stats.instanceUploadBytes
      if optimized.instanceMode != fallbackDraws: doAssert saved == 32*count*InstanceBytes
      else: doAssert saved == 0 # fallback has no instance GPU buffer, don't invent savings
      let rangeBefore = optimized.stats.instanceUploadBytes
      for step in 0..<3:
        let first = if step == 0: 119 elif step == 1: 120 else: 0
        let last = if step < 2: first else: count-1
        items[first].tint[0] = 0.2
        items[last].tint[1] = 0.4
        reference.updateInstances(items)
        when defined(js): trackRanges(ctx)
        doAssert optimized.updateInstancesIfChanged(items)
        when defined(js):
          if optimized.instanceMode != fallbackDraws:
            doAssert checkRange(ctx,first*InstanceBytes,(last-first+1)*InstanceBytes)
          untrackRanges(ctx)
        reference.renderInstances(64,64)
        let target = read()
        optimized.renderInstances(64,64)
        doAssert read() == target, "Partial upload changed pixels"
      let rangeBytes = optimized.stats.instanceUploadBytes-rangeBefore
      doAssert rangeBytes == (if optimized.instanceMode == fallbackDraws: 0 else: (count+2)*InstanceBytes)
      # Compact selection: source 120 is packed slot 1, offset is one record.
      reference.updateVisibleInstances(items,[119,120,121],3)
      optimized.updateVisibleInstances(items,[119,120,121],3)
      items[120].yaw += 0.2
      let compactBefore = optimized.stats.instanceUploadBytes
      when defined(js): trackRanges(ctx)
      doAssert optimized.updateVisibleInstancesIfChanged(items,[119,120,121],3)
      when defined(js):
        if optimized.instanceMode != fallbackDraws:
          doAssert checkRange(ctx,InstanceBytes,InstanceBytes)
        untrackRanges(ctx)
      let compactBytes = optimized.stats.instanceUploadBytes-compactBefore
      doAssert compactBytes == (if optimized.instanceMode == fallbackDraws: 0 else: InstanceBytes)
      reference.updateVisibleInstances(items,[119,120,121],3)
      reference.renderInstances(64,64)
      let compactImage = read()
      optimized.renderInstances(64,64)
      doAssert read() == compactImage
      # Moving snapshots, changing visibility and a fresh rebuild every step.
      for tick in 0..<8:
        for i in 0..<count: items[i].position[0] += 0.04
        grid.rebuild(bounds,items)
        var matrix = identity()
        if tick mod 2 == 0:
          matrix[0] = 0.25
          matrix[5] = 0.25
        let view = frustum(matrix)
        let visible = view.collectVisible(grid,indices,stats)
        doAssert view.collectVisible(bounds,items,oracle) == visible
        for i in 0..<visible: doAssert indices[i] == oracle[i]
        reference.updateInstances(items)
        reference.renderInstances(64,64,matrix)
        let target = read()
        discard optimized.updateVisibleInstancesIfChanged(items,indices,visible)
        optimized.renderInstances(64,64,matrix)
        doAssert read() == target, "Workload culling changed pixels"
        doAssert optimized.stats.instances == visible
        doAssert optimized.stats.drawCalls == (if optimized.instanceMode == fallbackDraws: visible else: int(visible > 0))
      echo "GPU_WORKLOAD ",$(%*{"compiler":compiler,"buildMode":buildMode,"api": $caps.api,"mode": $optimized.instanceMode,
        "forcedFallback":fallback,"instances":count,"staticRequests":32,"savedUploadBytes":saved,
        "skippedUpdates":optimized.stats.instanceSkippedUpdates,"pixelComparisons":13,
        "compactUploadBytes":compactBytes,"rangeRequests":3,"rangeUploadBytes":rangeBytes,
        "visible":optimized.stats.instances,"drawCalls":optimized.stats.drawCalls})
    finally:
      optimized.dispose()
      reference.dispose()
  echo "GPU workload static/moving/culling/fallback parity PASS: ",caps.api
