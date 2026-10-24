## Backend-neutral contracts. No GL handles escape into game data.
import std/[tables, math]

type
  Api* = enum webgl1, webgl2, gles2, gles3
  Tier* = enum t0, t1, t2
  Capabilities* = object
    api*: Api
    instancing*, vertexArrays*, rgb10a2*, ownerR8*: bool
  Vertex* = object
    position*: array[3, float32]
    normal*: array[3, float32]
    territory*: array[3, float32] # u, v, mask (0 = vertex color, 1 = owner palette)
    color*: array[3, float32] # Linear RGB; bake AO into this color.
  MeshData* = object
    vertices*: seq[Vertex]
    indices*: seq[uint16] # Optional; <=65535 unique vertices (0xffff is WebGL2 primitive restart), no uint32 extension required.
  FrameStats* = object
    drawCalls*, vertices*, bufferBytes*: int
    textureBytes*, deltaUploads*, deltaBytes*: int
    instances*, instanceUpdates*, instanceUploadBytes*: int

func baseline*(api: Api): Capabilities =
  let modern = api in {webgl2, gles3}
  Capabilities(api: api, instancing: modern, vertexArrays: modern,
    rgb10a2: modern, ownerR8: modern)

proc validate*(mesh: MeshData) =
  let count = if mesh.indices.len == 0: mesh.vertices.len else: mesh.indices.len
  if mesh.vertices.len == 0 or count == 0 or count mod 3 != 0 or count > high(int32).int:
    raise newException(ValueError, "Mesh must contain complete triangles fitting GLsizei")
  if mesh.indices.len > 0:
    if mesh.vertices.len > 65535: raise newException(ValueError, "Split mesh into uint16 chunks")
    for i in mesh.indices:
      if int(i) >= mesh.vertices.len: raise newException(ValueError, "Index outside vertex buffer")
  for v in mesh.vertices:
    for a in [v.position,v.normal,v.color,v.territory]:
      for x in a:
        if classify(x) in {fcNan,fcInf,fcNegInf}:
          raise newException(ValueError, "Non-finite vertex")

proc indexed*(mesh: MeshData): MeshData =
  ## Offline/static deduplication. Includes normals/material UVs: never weld hard edges.
  mesh.validate()
  if mesh.indices.len > 0: return mesh
  var lookup = initTable[Vertex,uint16]()
  for v in mesh.vertices:
    if not lookup.hasKey(v):
      if result.vertices.len >= 65535:
        raise newException(ValueError, "Split mesh into uint16 chunks")
      lookup[v] = uint16(result.vertices.len)
      result.vertices.add v
    result.indices.add lookup[v]

proc packed*(mesh: MeshData): seq[float32] =
  mesh.validate()
  result = newSeq[float32](mesh.vertices.len * 12)
  var i = 0
  for v in mesh.vertices:
    for a in [v.position, v.normal, v.color, v.territory]:
      for x in a:
        result[i] = x
        inc i
