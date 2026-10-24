import softgfx
proc demoMesh*(): MeshData =
  # Two faces of a low-poly wedge; positions already in clip space for bootstrap.
  for tri in [
    [[-0.7'f32,-0.5,0.0],[0.7'f32,-0.5,0.0],[0.0'f32,0.65,0.0]],
    [[0.0'f32,0.65,0.0],[0.7'f32,-0.5,0.0],[0.85'f32,0.1,0.1]]]:
    for pos in tri:
      result.vertices.add Vertex(position: pos, normal: [0.0'f32, 0.8, 0.6],
        color: [0.5'f32, 0.18, 0.12])

import std/math
import softgfx/geometry

proc addCar(mesh: var MeshData; origin: Vec3; yaw: float32; paint: Vec3) =
  template part(offset, size, color: Vec3) =
    block:
      let c = cos(yaw)
      let s = sin(yaw)
      let rotated: Vec3 = [c*offset[0]+s*offset[2], offset[1], -s*offset[0]+c*offset[2]]
      mesh.addBox(origin+rotated, size, color, yaw)
  part([0'f32,0.5,0], [1.45'f32,0.5,2.6], paint)
  part([0'f32,0.96,-0.15], [1.15'f32,0.45,1.35], paint*0.7'f32)
  part([0'f32,0.97,0.55], [1.02'f32,0.33,0.06], [0.08'f32,0.14,0.19])
  for x in [-0.77'f32,0.77]:
    for z in [-0.85'f32,0.85]:
      part([x,0.32'f32,z], [0.22'f32,0.52,0.5], [0.035'f32,0.045,0.055])
  for x in [-0.48'f32,0.48]:
    part([x,0.54'f32,1.32], [0.32'f32,0.16,0.06], [0.9'f32,0.78,0.45])

proc arenaMesh*(bakeLighting = false; includeCars = true): MeshData =
  result.addBox([0'f32,-0.22,0], [13'f32,0.4,13], [0.25'f32,0.34,0.29])
  # Top face samples the owner map. Bottom/sides keep vertex color.
  for v in result.vertices.mitems:
    if v.normal[1] > 0.9:
      v.territory = [(v.position[0]+6.5'f32)/13'f32, (v.position[2]+6.5'f32)/13'f32, 1'f32]
  if includeCars:
    result.addCar([0'f32,0,0], 0.4, [0.7'f32,0.16,0.09])
    result.addCar([-3.3'f32,0,-2.8], -0.9, [0.12'f32,0.35,0.65])
    result.addCar([3.1'f32,0,2.6], 1.6, [0.75'f32,0.5,0.08])
  for x in [-6'f32,6]:
    for z in [-6'f32,6]:
      result.addBox([x,0.6'f32,z], [0.55'f32,1.2,0.55], [0.25'f32,0.22,0.18])
      result.addBox([x,1.6'f32,z], [1.5'f32,1.4,1.5], [0.18'f32,0.33,0.19])
  if bakeLighting:
    let light = normalized([0.4'f32,0.8,0.5])
    for v in result.vertices.mitems:
      v.color = v.color * (0.45'f32 + 0.45'f32*max(0'f32,dot(v.normal,light)))

  result = result.indexed()

func arenaCamera*(angle = 0.6'f32; distance = 15'f32): Camera =
  Camera(eye: [sin(angle)*distance, distance*0.85'f32, cos(angle)*distance],
    target: [0'f32,0.5,0], up: [0'f32,1,0], fovY: 0.8,
    nearPlane: 0.1, farPlane: 100)

proc newSeqWithOwner*(count: int; owner: uint8): seq[uint8] =
  result = newSeq[uint8](count)
  for value in result.mitems: value = owner

proc arenaOwners*(): OwnerMap =
  var colors = defaultPalette()
  for id,rgb in [[70'u8,95,80], [145'u8,70,48], [48'u8,85,140], [150'u8,117,40]]:
    for channel in 0..2: colors[id*4+channel] = rgb[channel]
  result = newOwnerMap(31,23,colors) # Deliberately NPOT and odd width.
  result.applyDelta(1,1,5,7,newSeqWithOwner(5*7,1))
  result.applyDelta(23,15,7,5,newSeqWithOwner(7*5,2))
  result.applyDelta(20,2,8,5,newSeqWithOwner(8*5,3))

proc carMesh*(bakeLighting = false): MeshData =
  result.addCar([0'f32,0,0],0,[0.8'f32,0.8,0.8])
  if bakeLighting:
    let light = normalized([0.4'f32,0.8,0.5])
    for v in result.vertices.mitems:
      v.color = v.color*(0.45'f32+0.45'f32*max(0'f32,dot(v.normal,light)))
  result = result.indexed()

proc carSnapshot*(time: float32; items: var seq[Instance]) =
  ## Host demonstration only: not game physics. Storage is allocated once by host.
  doAssert items.len == 3
  for i in 0..2:
    let phase = time*0.6'f32 + float32(i)*2.0943951'f32
    let radius = 2.8'f32+float32(i)*0.65'f32
    # Update existing storage, not temporary Vec3/Instance objects in the JS hot path.
    const colors = [[0.875'f32,0.2,0.1125], [0.15'f32,0.4375,0.8125], [0.9375'f32,0.625,0.1]]
    items[i].position[0] = sin(phase)*radius
    items[i].position[1] = 0
    items[i].position[2] = cos(phase)*radius
    items[i].yaw = phase+PI.float32/2
    items[i].scale = 1
    for channel in 0..2: items[i].tint[channel] = colors[i][channel]
