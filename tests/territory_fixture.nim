## Shared GPU oracle: runs unchanged through WebGL and native GLES.
import std/math
import softgfx

type PixelReader* = proc(x,y: int): array[4,uint8] {.closure.}

proc probeMesh*(): MeshData =
  for uv in [[0'f32,0],[1'f32,0],[1'f32,1],[0'f32,1]]:
    result.vertices.add Vertex(position: [uv[0]*2-1,uv[1]*2-1,0'f32],
      normal: [0'f32,1,0], territory: [uv[0],uv[1],1'f32])
  result.indices = @[0'u16,1,2,0,2,3]

proc probeOwners*(): OwnerMap =
  var palette: Palette
  for i in 0..255:
    palette[i*4] = uint8(i)
    palette[i*4+1] = uint8((i*73) mod 256)
    palette[i*4+2] = uint8((i*151) mod 256)
    palette[i*4+3] = 255
  result = newOwnerMap(17,17,palette)
  var data = newSeq[uint8](17*17)
  for i in 0..<data.len: data[i] = uint8(i mod 256)
  result.applyDelta(0,0,17,17,data)

func reference(id: uint8; palette: Palette; api: Api): array[3,int] =
  var lighting = [1.0,1.0,1.0]
  if api in {webgl2,gles3}:
    let wrap = clamp((0.8/sqrt(0.4*0.4+0.8*0.8+0.5*0.5)+0.45)/1.45,0.0,1.0)
    let sun = wrap*wrap*(3-2*wrap)
    lighting = [0.35+0.8*sun,0.43+0.65*sun,0.55+0.45*sun]
  for ch in 0..2:
    let linear = float(palette[int(id)*4+ch])/255*lighting[ch]
    let encoded = if linear <= 0.0031308: linear*12.92 else: 1.055*pow(linear,1/2.4)-0.055
    result[ch] = int(round(clamp(encoded,0.0,1.0)*255))

proc runTerritoryProbe*(ctx: Context; caps: Capabilities; read: PixelReader) =
  let map = probeOwners()
  let mesh = probeMesh()
  var r = initRenderer(ctx,caps,mesh,map)
  proc verify() =
    r.render(64,64)
    let cells = map.pixels
    for y in 0..<17:
      for x in 0..<17:
        let pixel = read(int((float(x)+0.5)*64/17),int((float(y)+0.5)*64/17))
        let expected = reference(cells[y*17+x],map.palette,caps.api)
        for ch in 0..2:
          # One LSB dither + mediump shader/driver rounding allowance.
          doAssert abs(int(pixel[ch])-expected[ch]) <= 4, "Owner/palette sampling mismatch"
        doAssert pixel[3] == 255
  verify() # Includes every owner ID, NPOT, all row orientations.
  let initial = map.pixels
  var rejected = false
  try: r.updateTerritory(16,0,3,5,newSeq[uint8](15))
  except ValueError: rejected = true
  doAssert rejected and map.pixels == initial and r.stats.deltaUploads == 0
  r.updateTerritory(5,7,3,5,@[255'u8,128,0, 1,254,127, 0,255,1, 128,127,254, 255,255,255])
  doAssert r.stats.deltaUploads == 1 and r.stats.deltaBytes == 15
  doAssert r.stats.bufferBytes == 4*48+6*2
  doAssert r.stats.textureBytes == 17*17+1024
  verify() # Unchanged texels checked too: no full-row overwrite/alignment corruption.
  r.dispose()
  r.dispose()
  # Recreate from retained CPU data, as a host does after context loss.
  r = initRenderer(ctx,caps,mesh,map)
  verify()
  r.dispose()
  echo "territory GPU: OK (", caps.api, ")"
