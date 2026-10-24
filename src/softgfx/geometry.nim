## Static box batching. World-space positions/normals; rotation around Y only.
## Not instancing: useful for a baseline and static arena chunks.
import std/math
import types, math3d

func rotateY(v: Vec3; angle: float32): Vec3 =
  let c = cos(angle)
  let s = sin(angle)
  [c*v[0]+s*v[2], v[1], -s*v[0]+c*v[2]]

proc addBox*(mesh: var MeshData; center, size, color: Vec3; yaw = 0'f32) =
  if not finite(center) or not finite(size) or not finite(color) or not finite(yaw) or
      size[0] <= 0 or size[1] <= 0 or size[2] <= 0:
    raise newException(ValueError, "Invalid box")
  # Corners ordered counterclockwise as seen from outside each face.
  const normals = [[1'f32,0,0], [-1'f32,0,0], [0'f32,1,0],
                   [0'f32,-1,0], [0'f32,0,1], [0'f32,0,-1]]
  const corners = [
    [[1'f32,-1,-1],[1'f32,1,-1],[1'f32,1,1],[1'f32,-1,1]],
    [[-1'f32,-1,1],[-1'f32,1,1],[-1'f32,1,-1],[-1'f32,-1,-1]],
    [[-1'f32,1,1],[1'f32,1,1],[1'f32,1,-1],[-1'f32,1,-1]],
    [[-1'f32,-1,-1],[1'f32,-1,-1],[1'f32,-1,1],[-1'f32,-1,1]],
    [[1'f32,-1,1],[1'f32,1,1],[-1'f32,1,1],[-1'f32,-1,1]],
    [[-1'f32,-1,-1],[-1'f32,1,-1],[1'f32,1,-1],[1'f32,-1,-1]]]
  for face in 0..5:
    let n = rotateY(normals[face], yaw)
    for index in [0,1,2,0,2,3]:
      var p = corners[face][index]
      for axis in 0..2: p[axis] *= size[axis] * 0.5'f32
      mesh.vertices.add Vertex(position: center + rotateY(p, yaw), normal: n, color: color)
