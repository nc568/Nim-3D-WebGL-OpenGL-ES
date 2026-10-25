## Per-program camera cache; same pixel/counter contract on WebGL and GLES.
import std/math
import softgfx, softgfx/geometry
import instance_fixture
when defined(js):
  proc track(gl: Context) {.importjs: """(function(g){const f=g.uniformMatrix4fv;g._camera={calls:0,fail:0};g._restoreCamera=()=>{g.uniformMatrix4fv=f;};g.uniformMatrix4fv=function(...args){g._camera.calls++;const fail=g._camera.fail;g._camera.fail=0;if(fail===1)throw Error('matrix before');const v=f.apply(g,args);if(fail===2)throw Error('matrix after');return v;};})(#)""".}
  proc calls(gl: Context): int {.importjs: "#._camera.calls".}
  proc failNext(gl: Context; mode: int) {.importjs: "(#._camera.fail = #)".}
  proc untrack(gl: Context) {.importjs: "#._restoreCamera()".}
proc draw(r: var Renderer; batch: bool; matrix: Mat4) =
  if batch: r.renderInstances(64,64,matrix)
  else: r.render(64,64,matrix)
proc runCameraProbe*(ctx: Context; caps: Capabilities; read: FrameReader) =
  var mesh: MeshData
  mesh.addBox([0'f32,0,0],[0.4'f32,0.4,0.4],[0.8'f32,0.3,0.2])
  for batch in [false,true]:
    for fallback in [false,true]:
      var r = initRenderer(ctx,caps,mesh,instanceCapacity=(if batch: 2 else: 0),forceFallback=fallback)
      var reference = initRenderer(ctx,caps,mesh,instanceCapacity=(if batch: 2 else: 0),forceFallback=fallback)
      if batch:
        let poses = [instance([-0.4'f32,0,0]),instance([0.4'f32,0,0])]
        r.updateInstances(poses); reference.updateInstances(poses)
      when defined(js): track(ctx)
      try:
        var matrix = identity()
        r.draw(batch,matrix)
        let initial = read()
        for i in 0..<100: r.draw(batch,matrix)
        doAssert r.cameraStats == (1,100)
        when defined(js): doAssert calls(ctx) == 1
        doAssert read() == initial
        matrix[12] = 0.25
        r.draw(batch,matrix)
        let changed = read()
        doAssert changed != initial
        reference.draw(batch,matrix)
        doAssert read() == changed
        r.draw(batch,matrix) # another program does not invalidate this cache
        doAssert read() == changed and r.cameraStats == (2,101)
        var alias = r
        alias.invalidateCamera()
        r.draw(batch,matrix)
        doAssert r.cameraStats == (3,101) and read() == changed
        matrix[0] = NaN.float32
        var rejected = false
        try: r.draw(batch,matrix)
        except ValueError: rejected = true
        doAssert rejected and r.cameraStats == (3,101)
        matrix = identity()
        when defined(js):
          for failure in [1,2]:
            r.invalidateCamera()
            failNext(ctx,failure)
            rejected = false
            try: r.draw(batch,matrix)
            except: rejected = true
            doAssert rejected
            let attempts = calls(ctx)
            r.draw(batch,matrix) # SAME shadow after failure still must upload
            doAssert calls(ctx) == attempts+1 and read() == initial
        r.draw(batch,identity())
        doAssert read() == initial
      finally:
        when defined(js): untrack(ctx)
        r.dispose(); reference.dispose()
  echo "Camera cache pixels / 100 skipped uniforms / interleave / invalidation / retry PASS: ",caps.api
