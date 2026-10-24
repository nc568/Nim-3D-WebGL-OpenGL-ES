## Same GPU/counter oracle on WebGL and native GLES, core and fallback paths.
import softgfx, softgfx/geometry
import instance_fixture
when defined(js):
  proc track(gl: Context) {.importjs: """(function(g){g._dirty={u:0,b:0,failU:0,failB:0,after:false,bytes:0,offset:0};const u=g.uniform4f,b=g.bufferSubData;g._dirty.restore=()=>{g.uniform4f=u;g.bufferSubData=b;};g.uniform4f=function(...a){g._dirty.u++;if(--g._dirty.failU===0)throw Error('injected uniform failure');return u.apply(g,a);};g.bufferSubData=function(...a){g._dirty.b++;g._dirty.offset=a[1];g._dirty.bytes=a[2].byteLength;if(--g._dirty.failB===0)throw Error('injected buffer failure');const v=b.apply(g,a);if(g._dirty.after){g._dirty.after=false;throw Error('injected post-upload failure');}return v;};})(#)""".}
  proc uniforms(gl: Context): int {.importjs: "#._dirty.u".}
  proc buffers(gl: Context): int {.importjs: "#._dirty.b".}
  proc failUniform(gl: Context) {.importjs: "(#._dirty.failU=2)".}
  proc failAfterBuffer(gl: Context) {.importjs: "(#._dirty.after=true)".}
  proc lastBytes(gl: Context): int {.importjs: "#._dirty.bytes".}
  proc failBuffer(gl: Context) {.importjs: "(#._dirty.failB=1)".}
  proc trackDeletes(gl: Context) {.importjs: """(function(g){g._deletes=0;const names=['deleteBuffer','deleteProgram','deleteTexture'];const old=names.map(n=>g[n]);g._restoreDeletes=()=>names.forEach((n,i)=>g[n]=old[i]);names.forEach((n,i)=>g[n]=function(...a){g._deletes++;return old[i].apply(g,a);});})(#)""".}
  proc deletions(gl: Context): int {.importjs: "#._deletes".}
  proc restoreDeletes(gl: Context) {.importjs: "#._restoreDeletes()".}
  proc untrack(gl: Context) {.importjs: "#._dirty.restore()".}


proc runDirtyProbe*(ctx: Context; caps: Capabilities; read: FrameReader) =
  var mesh: MeshData
  mesh.addBox([0'f32,0,0],[0.5'f32,0.5,0.5],[0.7'f32,0.5,0.3])
  var poses = @[instance([-0.4'f32,0,0],yaw=0.3,scale=0.7),instance([0.4'f32,0,0])]
  for fallback in [false,true]:
    var r = initRenderer(ctx,caps,mesh,instanceCapacity=2,forceFallback=fallback)
    when defined(js): track(ctx)
    doAssert r.updateInstancesIfChanged(poses)
    r.renderInstances(64,64)
    let image = read()
    let bytes = r.stats.instanceUploadBytes
    let updates = r.stats.instanceUpdates
    when defined(js):
      let beforeBuffers = buffers(ctx)
    for i in 0..<100:
      doAssert not r.updateInstancesIfChanged(poses)
      doAssert not r.updateVisibleInstancesIfChanged(poses,[0,1],2)
    when defined(js): doAssert buffers(ctx) == beforeBuffers
    doAssert r.stats.instanceSkippedUpdates == 200
    doAssert r.stats.instanceUploadBytes == bytes and r.stats.instanceUpdates == updates
    r.renderInstances(64,64)
    doAssert read() == image
    # Force APIs keep their prior semantics, even for identical data.
    r.updateInstances(poses)
    doAssert r.stats.instanceUpdates == updates+1
    doAssert not r.updateInstancesIfChanged(poses)
    doAssert r.updateVisibleInstancesIfChanged(poses,[1],1)
    doAssert not r.updateVisibleInstancesIfChanged(poses,[1],1)
    r.renderInstances(64,64)
    doAssert r.stats.instances == 1
    doAssert r.updateVisibleInstancesIfChanged(poses,[],0)
    doAssert not r.updateVisibleInstancesIfChanged(poses,[],0)
    r.renderInstances(64,64,clear=false)
    doAssert r.stats.drawCalls == 0
    doAssert r.updateInstancesIfChanged(poses)
    r.renderInstances(64,64)
    doAssert read() == image
    var effects = SceneEffects(fogEnabled:true,fogNear:0,fogFar:5,
      eye:[0'f32,0,2],fogColor:[0.3'f32,0.4,0.5],blobCount:1)
    effects.blobs[0] = BlobShadow(radiusX:1,radiusZ:1,strength:0.4)
    r.updateEffects(effects)
    doAssert r.stats.effectUniformCalls == 5 # fog + eye + color + one blob pair
    r.renderInstances(64,64)
    let effected = read()
    when defined(js):
      let beforeUniforms = uniforms(ctx)
      doAssert beforeUniforms == 5
    for i in 0..<100: r.updateEffects(effects)
    when defined(js): doAssert uniforms(ctx) == beforeUniforms
    doAssert r.stats.effectUpdates == 1 and r.stats.effectSkippedUpdates == 100
    doAssert r.stats.effectUniformCalls == 5
    r.renderInstances(64,64)
    doAssert read() == effected
    effects.eye[2] = 3
    r.updateEffects(effects)
    doAssert r.stats.effectUniformCalls == 6 # only eye changed
    effects.blobs[0].center[0] = 0.1
    r.updateEffects(effects)
    doAssert r.stats.effectUniformCalls == 8 # only one blob pair
    r.renderInstances(64,64)
    let changed = read()
    r.updateEffects(effects,force=true)
    doAssert r.stats.effectUniformCalls == 19 # full resync, including inactive slots
    r.renderInstances(64,64)
    doAssert read() == changed
    r.updateEffects(SceneEffects())
    r.renderInstances(64,64)
    doAssert read() == image
    when defined(js):
      # Throw after one uniform succeeds: retry must resynchronize ALL slots.
      failUniform(ctx)
      var failed = false
      try: r.updateEffects(effects)
      except: failed = true
      doAssert failed
      let partial = uniforms(ctx)
      r.updateEffects(effects)
      doAssert uniforms(ctx) == partial+11
      r.renderInstances(64,64)
      doAssert read() == changed
      r.updateEffects(SceneEffects())
      if not fallback:
        poses[0].position[0] += 0.1
        failBuffer(ctx)
        failed = false
        try: discard r.updateInstancesIfChanged(poses)
        except: failed = true
        doAssert failed
        let attempts = buffers(ctx)
        doAssert r.updateInstancesIfChanged(poses)
        doAssert buffers(ctx) == attempts+1
        doAssert lastBytes(ctx) == poses.len*InstanceBytes # uncertain GPU requires full resync
        doAssert not r.updateInstancesIfChanged(poses)
        poses[0].position[0] -= 0.1
        discard r.updateInstancesIfChanged(poses)
        # The GL call may succeed before a wrapper throws. Retrying a DIFFERENT
        # snapshot must repair the entire buffer, not merely the newest diff.
        poses[1].position[0] += 0.2
        failAfterBuffer(ctx)
        failed = false
        try: discard r.updateInstancesIfChanged(poses)
        except: failed = true
        doAssert failed and lastBytes(ctx) == InstanceBytes
        let failedAttempts = buffers(ctx)
        let savedScale = poses[0].scale
        poses[0].scale = 0
        failed = false
        try: discard r.updateInstancesIfChanged(poses)
        except ValueError: failed = true
        doAssert failed and buffers(ctx) == failedAttempts
        poses[0].scale = savedScale
        poses[1].position[0] -= 0.2
        doAssert r.updateInstancesIfChanged(poses)
        doAssert lastBytes(ctx) == poses.len*InstanceBytes
        r.renderInstances(64,64)
        doAssert read() == image
        doAssert not r.updateInstancesIfChanged(poses)
      untrack(ctx)
    # Counters remain saturating on JS int32/native int.
    r.stats.instanceSkippedUpdates = high(int)
    r.stats.effectSkippedUpdates = high(int)
    doAssert not r.updateInstancesIfChanged(poses)
    r.updateEffects(SceneEffects())
    doAssert r.stats.instanceSkippedUpdates == high(int) and r.stats.effectSkippedUpdates == high(int)
    var alias = r
    when defined(js): trackDeletes(ctx)
    alias.dispose()
    when defined(js):
      let deleted = deletions(ctx)
      doAssert deleted > 0
    r.dispose() # not a second GL deletion
    when defined(js):
      doAssert deletions(ctx) == deleted
      restoreDeletes(ctx)
    var rejected = false
    try: r.renderInstances(64,64)
    except ValueError: rejected = true
    doAssert rejected
    rejected = false
    try: alias.updateEffects(SceneEffects())
    except ValueError: rejected = true
    doAssert rejected
    r = initRenderer(ctx,caps,mesh,instanceCapacity=2,forceFallback=fallback)
    doAssert r.updateInstancesIfChanged(poses) # a new owner cannot reuse the old cache
    r.renderInstances(64,64)
    doAssert read() == image
    # Replacing one alias must not revive the old resource.
    rejected = false
    try: alias.updateInstances(poses)
    except ValueError: rejected = true
    doAssert rejected
    r.dispose()
    alias = r
    r.abandon() # already disposed; no live GPU allocation leaked by this test
    alias.dispose()
  echo "Dirty GPU skips / count transitions / effects delta / forced parity / recreation PASS: ",caps.api
