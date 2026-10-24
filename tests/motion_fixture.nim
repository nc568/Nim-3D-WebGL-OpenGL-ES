## Pixel oracle: midpoint of matched snapshots vs independently specified poses.
import std/math
import softgfx, softgfx/[geometry, motion]
import instance_fixture

proc runMotionProbe*(ctx: Context; caps: Capabilities; read: FrameReader) =
  var mesh: MeshData
  mesh.addBox([0'f32,0,0],[0.25'f32,0.3,0.45],[0.7'f32,0.6,0.5])
  let before = @[instance([-0.6'f32,-0.2,0],yaw=350'f32*PI.float32/180,scale=0.5,tint=[0.2'f32,0.4,0.6]),
    instance([0.3'f32,0.2,0],yaw=0,scale=0.75)]
  let after = @[instance([-0.2'f32,0.2,0],yaw=10'f32*PI.float32/180,scale=1.5,tint=[0.8'f32,0.6,0.4]),
    instance([0.5'f32,0.4,0],yaw=PI.float32,scale=1.25)]
  let expected = @[instance([-0.4'f32,0,0],yaw=0,scale=1,tint=[0.5'f32,0.5,0.5]),
    instance([0.4'f32,0.3,0],yaw= -PI.float32/2,scale=1)]
  var reference = initRenderer(ctx,caps,mesh,instanceCapacity=2,forceFallback=true,unlit=true)
  reference.updateInstances(expected)
  reference.renderInstances(64,64)
  let target = read()
  var poses = newSeq[Instance](2)
  for fallback in [false,true]:
    var r = initRenderer(ctx,caps,mesh,instanceCapacity=2,forceFallback=fallback,unlit=true)
    interpolateInstances(before,after,0.5,poses)
    r.updateInstances(poses)
    r.renderInstances(64,64)
    let actual = read()
    for i in 0..<actual.len:
      doAssert abs(int(actual[i])-int(target[i])) <= 2, "Interpolated pose/color GPU reference mismatch"
    # Snap endpoints and then interpolate again: no retained transform state.
    for alpha in [0.0,1.0]:
      interpolateInstances(before,after,alpha,poses)
      r.updateInstances(poses)
      r.renderInstances(64,64)
      let endImage = read()
      reference.updateInstances(if alpha == 0: before else: after)
      reference.renderInstances(64,64)
      doAssert read() == endImage
    r.dispose()
  reference.dispose()
  echo "Motion midpoint/linear-tint/endpoints/core-fallback GPU: PASS ",caps.api
