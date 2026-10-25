## Browser owns the canvas. This module never touches UI DOM or creates a WASM module.
import std/jsffi
import ../[types, math3d, territory, instances, environment]
import std/math

type
  Context* = JsObject
  Buffer* = JsObject
  Program* = JsObject
  TerritoryBinding* = object
    owners, palette: JsObject
    modern: bool
  InstanceStream* = object
    mode*: InstanceMode
    buffer, extension, storage, view: JsObject
    used, first: int
    copied: bool
  MatrixBinding* = ref object
    location, data: JsObject
    valid: bool
    uploads*, skips*: int

proc acquire*(canvas: JsObject; forceLegacy = false): tuple[ctx: Context, caps: Capabilities] =
  let options = newJsObject()
  options.antialias = false
  options.alpha = false
  var gl: JsObject
  if not forceLegacy: gl = canvas.getContext("webgl2", options)
  if not gl.isNil:
    return (gl, baseline(webgl2))
  gl = canvas.getContext("webgl", options)
  if gl.isNil: raise newException(ValueError, "WebGL unavailable")
  var caps = baseline(webgl1)
  caps.instancing = not gl.getExtension("ANGLE_instanced_arrays").isNil
  (gl, caps)

proc compile(gl: Context; kind: int; source: string): JsObject =
  result = gl.createShader(kind)
  gl.shaderSource(result, cstring(source))
  gl.compileShader(result)
  if not gl.getShaderParameter(result, 0x8B81).to(bool):
    let message = $gl.getShaderInfoLog(result).to(cstring)
    gl.deleteShader(result)
    raise newException(ValueError, message)

proc createProgram*(gl: Context; vs, fs: string): Program =
  let v = compile(gl, 0x8B31, vs)
  var f: JsObject
  try:
    f = compile(gl, 0x8B30, fs)
    result = gl.createProgram()
    gl.attachShader(result, v)
    gl.attachShader(result, f)
    gl.bindAttribLocation(result, 0, "aPosition")
    gl.bindAttribLocation(result, 1, "aNormal")
    gl.bindAttribLocation(result, 2, "aColor")
    gl.bindAttribLocation(result, 3, "aTerritory")
    gl.bindAttribLocation(result, 4, "aInstancePosition")
    gl.bindAttribLocation(result, 5, "aInstanceRotationScale")
    gl.bindAttribLocation(result, 6, "aInstanceTint")
    gl.linkProgram(result)
    if not gl.getProgramParameter(result, 0x8B82).to(bool):
      let message = $gl.getProgramInfoLog(result).to(cstring)
      gl.deleteProgram(result)
      raise newException(ValueError, message)
  finally:
    gl.deleteShader(v)
    if not f.isNil: gl.deleteShader(f)

proc floatArray(data: seq[float32]): JsObject {.importjs: "new Float32Array(#)".}
proc createBuffer*(gl: Context; data: seq[float32]): Buffer =
  result = gl.createBuffer()
  gl.bindBuffer(0x8892, result)
  gl.bufferData(0x8892, floatArray(data), 0x88E4)

proc indexArray(data: seq[uint16]): JsObject {.importjs: "new Uint16Array(#)".}
proc createIndices*(gl: Context; data: seq[uint16]): Buffer =
  if data.len == 0: return
  result = gl.createBuffer()
  gl.bindBuffer(0x8893, result)
  gl.bufferData(0x8893, indexArray(data), 0x88E4)

proc byteArray(data: seq[uint8]): JsObject {.importjs: "new Uint8Array(#)".}
proc colorArray(data: Palette): JsObject {.importjs: "new Uint8Array(#)".}
proc texture(gl: Context; unit: int): JsObject =
  result = gl.createTexture()
  gl.activeTexture(unit)
  gl.bindTexture(0x0DE1, result)
  for name in [0x2800,0x2801]: gl.texParameteri(0x0DE1,name,0x2600) # NEAREST
  for name in [0x2802,0x2803]: gl.texParameteri(0x0DE1,name,0x812F) # CLAMP_TO_EDGE

proc createTerritory*(gl: Context; p: Program; modern: bool; m: OwnerMap): TerritoryBinding =
  let limit = gl.getParameter(0x0D33).to(int)
  if m.width > limit or m.height > limit or limit < 256:
    raise newException(ValueError, "Owner map exceeds MAX_TEXTURE_SIZE")
  result.modern = modern
  result.owners = texture(gl,0x84C0)
  gl.pixelStorei(0x0CF5,1) # odd-width owner rows must be tightly packed
  gl.texImage2D(0x0DE1,0,(if modern: 0x8229 else: 0x1909),m.width,m.height,0,
    (if modern: 0x1903 else: 0x1909),0x1401,byteArray(m.pixels))
  result.palette = texture(gl,0x84C1)
  gl.texImage2D(0x0DE1,0,0x1908,256,1,0,0x1908,0x1401,colorArray(m.palette))
  gl.pixelStorei(0x0CF5,4)
  gl.useProgram(p)
  gl.uniform1i(gl.getUniformLocation(p,"uOwners"),0)
  gl.uniform1i(gl.getUniformLocation(p,"uPalette"),1)
  return result

proc uploadDelta*(gl: Context; t: TerritoryBinding; x,y,w,h: int; data: seq[uint8]) =
  gl.activeTexture(0x84C0)
  gl.bindTexture(0x0DE1,t.owners)
  gl.pixelStorei(0x0CF5,1)
  gl.texSubImage2D(0x0DE1,0,x,y,w,h,(if t.modern: 0x1903 else: 0x1909),0x1401,byteArray(data))
  gl.pixelStorei(0x0CF5,4)

proc destroyTerritory*(gl: Context; t: TerritoryBinding) =
  gl.deleteTexture(t.owners)
  gl.deleteTexture(t.palette)

proc matrixStorage(): JsObject {.importjs: "new Float32Array(16)".}
proc setElement(data: JsObject; i: int; value: float32) {.importjs: "(#[#] = #)".}
proc matrixBinding*(gl: Context; p: Program): MatrixBinding =
  new(result)
  result.location = gl.getUniformLocation(p, "uViewProjection")
  result.data = matrixStorage()

proc invalidateMatrix*(binding: MatrixBinding) =
  if not binding.isNil: binding.valid = false

proc matrixElement(data: JsObject; i: int): float32 {.importjs: "#[#]".}
proc canonical(value: float32): float32 {.importjs: "Math.fround(#)".}
proc submitMatrix(gl: Context; binding: MatrixBinding; matrix: Mat4) =
  if binding.location.isNil: return # shader has no camera uniform (e.g. sky)
  var changed = not binding.valid
  for i in 0..15:
    let value = canonical(matrix[i])
    if matrixElement(binding.data,i) != value:
      setElement(binding.data,i,value)
      changed = true
  if not changed:
    if binding.skips < high(int): inc binding.skips
    return
  binding.valid = false # failures, even after submission, require retry
  gl.uniformMatrix4fv(binding.location,false,binding.data)
  binding.valid = true
  if binding.uploads < high(int): inc binding.uploads

proc instanceStorage(count: int): JsObject {.importjs: "new Float32Array(#)".}
proc createInstanceStream*(gl: Context; api: Api; capacity: int; forceFallback: bool): InstanceStream =
  if not forceFallback:
    if api == webgl2: result.mode = coreInstancing
    else:
      result.extension = gl.getExtension("ANGLE_instanced_arrays")
      if not result.extension.isNil: result.mode = angleInstancing
  if result.mode != fallbackDraws:
    result.buffer = gl.createBuffer()
    gl.bindBuffer(0x8892,result.buffer)
    gl.bufferData(0x8892,capacity*InstanceBytes,0x88E8)


proc packedObject(data: seq[float32]): JsObject {.importjs: "#".}
proc isFloat32(data: seq[float32]): bool {.importjs: "(# instanceof Float32Array)".}
proc sameStorage(a,b: JsObject): bool {.importjs: "(# === #)".}
proc storageLength(data: JsObject): int {.importjs: "#.length".}

proc copyInstanceStorage(stream: var InstanceStream; data: seq[float32]; first,count: int) =
  # Compatibility for direct backend callers using Nim's ordinary Float64Array seq.
  if not stream.copied or storageLength(stream.storage) != data.len:
    stream.storage = instanceStorage(data.len)
    stream.used = -1
  stream.copied = true
  for i in first*InstanceFloats..<(first+count)*InstanceFloats: setElement(stream.storage,i,data[i])

proc uploadInstancesRange*(gl: Context; stream: var InstanceStream; data: seq[float32]; first, count: int) =
  if stream.mode == fallbackDraws or count == 0: return
  if isFloat32(data):
    let source = packedObject(data)
    if not sameStorage(stream.storage,source):
      stream.storage = source
      stream.used = -1 # views must follow backing identity, not merely first/count
    stream.copied = false
  else:
    copyInstanceStorage(stream,data,first,count)
  if stream.used != count or stream.first != first:
    stream.view = stream.storage.subarray(first*InstanceFloats,(first+count)*InstanceFloats)
    stream.first = first
    stream.used = count
  gl.bindBuffer(0x8892,stream.buffer)
  gl.bufferSubData(0x8892,first*InstanceBytes,stream.view)

proc uploadInstances*(gl: Context; stream: var InstanceStream; data: seq[float32]; count: int) =
  gl.uploadInstancesRange(stream,data,0,count)

proc destroyInstanceStream*(gl: Context; stream: InstanceStream) =
  gl.deleteBuffer(stream.buffer)

proc divisor(gl: Context; stream: InstanceStream; index, value: int) =
  if stream.mode == coreInstancing: gl.vertexAttribDivisor(index,value)
  elif stream.mode == angleInstancing: stream.extension.vertexAttribDivisorANGLE(index,value)

proc identityInstance(gl: Context) =
  for i in 4..6: gl.disableVertexAttribArray(i)
  gl.vertexAttrib3f(4,0.0,0.0,0.0)
  gl.vertexAttrib3f(5,1.0,0.0,1.0)
  gl.vertexAttrib3f(6,1.0,1.0,1.0)

proc prepare(gl: Context; p: Program; b: Buffer; count, width, height: int; binding: MatrixBinding; matrix: Mat4; indices: Buffer; indexed: bool; territory: TerritoryBinding; clear: bool) =
  gl.viewport(0, 0, width, height)
  gl.disable(0x0BE2) # blend
  gl.disable(0x0C11) # scissor; UI may have used it
  gl.enable(0x0B71) # depth
  gl.depthMask(true)
  gl.depthFunc(0x0201) # LESS
  if clear:
    gl.clearDepth(1.0)
    gl.clearColor(0.65, 0.74, 0.82, 1.0)
    gl.clear(0x4100)
  gl.useProgram(p)
  submitMatrix(gl,binding,matrix)
  gl.activeTexture(0x84C0)
  gl.bindTexture(0x0DE1,territory.owners)
  gl.activeTexture(0x84C1)
  gl.bindTexture(0x0DE1,territory.palette)
  gl.bindBuffer(0x8892, b)
  for i in 0..3:
    gl.enableVertexAttribArray(i)
    gl.vertexAttribPointer(i, 3, 0x1406, false, 48, i*12)

proc drawGeometry(gl: Context; count: int; indices: Buffer; indexed: bool) =
  if indexed:
    gl.bindBuffer(0x8893,indices)
    gl.drawElements(0x0004,count,0x1403,0)
  else: gl.drawArrays(0x0004,0,count)

proc draw*(gl: Context; p: Program; b: Buffer; count, width, height: int; binding: MatrixBinding; matrix: Mat4; indices: Buffer; indexed: bool; territory: TerritoryBinding; clear: bool; background = false) =
  prepare(gl,p,b,count,width,height,binding,matrix,indices,indexed,territory,clear)
  if background:
    gl.disable(0x0B71)
    gl.depthMask(false)
  identityInstance(gl)
  drawGeometry(gl,count,indices,indexed)

proc drawInstances*(gl: Context; p: Program; b: Buffer; count, width, height: int; binding: MatrixBinding; matrix: Mat4; indices: Buffer; indexed: bool; territory: TerritoryBinding; stream: InstanceStream; data: seq[float32]; instances: int; clear: bool) =
  prepare(gl,p,b,count,width,height,binding,matrix,indices,indexed,territory,clear)
  identityInstance(gl)
  if instances == 0: return
  if stream.mode == fallbackDraws:
    for item in 0..<instances:
      let offset = item*InstanceFloats
      for attribute in 0..2:
        let i = offset+attribute*3
        gl.vertexAttrib3f(4+attribute,data[i],data[i+1],data[i+2])
      drawGeometry(gl,count,indices,indexed)
  else:
    gl.bindBuffer(0x8892,stream.buffer)
    for i in 0..2:
      gl.enableVertexAttribArray(4+i)
      gl.vertexAttribPointer(4+i,3,0x1406,false,InstanceBytes,i*12)
      divisor(gl,stream,4+i,1)
    if indexed: gl.bindBuffer(0x8893,indices)
    if stream.mode == coreInstancing:
      if indexed: gl.drawElementsInstanced(0x0004,count,0x1403,0,instances)
      else: gl.drawArraysInstanced(0x0004,0,count,instances)
    else:
      if indexed: stream.extension.drawElementsInstancedANGLE(0x0004,count,0x1403,0,instances)
      else: stream.extension.drawArraysInstancedANGLE(0x0004,0,count,instances)
    for i in 4..6: divisor(gl,stream,i,0)
  identityInstance(gl) # Never leak per-instance divisors/attributes to the next pass.

proc destroy*(gl: Context; p: Program; b: Buffer) =
  gl.deleteProgram(p)
  gl.deleteBuffer(b)

proc destroyIndices*(gl: Context; b: Buffer) = gl.deleteBuffer(b)

include post_web

type EffectBinding* = object
  fog, eye, color: JsObject
  rects, planes: array[MaxBlobs,JsObject]

proc effectBinding*(gl: Context; p: Program): EffectBinding =
  result.fog = gl.getUniformLocation(p,"uFog")
  result.eye = gl.getUniformLocation(p,"uEye")
  result.color = gl.getUniformLocation(p,"uFogColor")
  for i in 0..<MaxBlobs:
    result.rects[i] = gl.getUniformLocation(p,cstring("uBlobRects[" & $i & "]"))
    result.planes[i] = gl.getUniformLocation(p,cstring("uBlobPlanes[" & $i & "]"))

proc updateEffects*(gl: Context; p: Program; b: EffectBinding; s: SceneEffects;
                    changes: EffectChanges): int =
  gl.useProgram(p)
  if changes.parameters:
    gl.uniform4f(b.fog,(if s.fogEnabled: s.fogNear else: 0'f32),
      (if s.fogEnabled: 1'f32/(s.fogFar-s.fogNear) else: 0'f32),float32(s.blobCount),0)
    inc result
  if changes.eye:
    if s.fogEnabled: gl.uniform4f(b.eye,s.eye[0],s.eye[1],s.eye[2],0)
    else: gl.uniform4f(b.eye,0,0,0,0)
    inc result
  if changes.color:
    if s.fogEnabled: gl.uniform4f(b.color,s.fogColor[0],s.fogColor[1],s.fogColor[2],0)
    else: gl.uniform4f(b.color,0,0,0,0)
    inc result
  for i in 0..<MaxBlobs:
    if changes.blobs[i]:
      if i < s.blobCount:
        template blob: untyped = s.blobs[i]
        gl.uniform4f(b.rects[i],blob.center[0],blob.center[2],blob.radiusX,blob.radiusZ)
        gl.uniform4f(b.planes[i],blob.center[1],blob.strength,cos(blob.yaw),sin(blob.yaw))
      else:
        gl.uniform4f(b.rects[i],0,0,0,0)
        gl.uniform4f(b.planes[i],0,0,0,0)
      result += 2
