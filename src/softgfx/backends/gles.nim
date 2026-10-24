## Host supplies a current GLES context and a function resolver (EGL/SDL).
## Resolve once at startup. No platform library names or lazy imports in hot paths.
import ../[types, math3d, territory, instances, environment]
import std/math
type
  Resolver* = proc(name: cstring): pointer {.cdecl.}
  Buffer* = uint32
  Program* = uint32
  InstanceStream* = object
    mode*: InstanceMode
    buffer: Buffer
  TerritoryBinding* = object
    owners, palette: uint32
    modern: bool
  MatrixBinding* = int32
  Context* = object
    glUniform4f: proc(location: int32; x,y,z,w: float32) {.cdecl.}
    glGenFramebuffers: proc(count: int32; names: ptr uint32) {.cdecl.}
    glDeleteFramebuffers: proc(count: int32; names: ptr uint32) {.cdecl.}
    glBindFramebuffer: proc(target, name: uint32) {.cdecl.}
    glFramebufferTexture2D: proc(target, attachment, textureTarget, texture: uint32; level: int32) {.cdecl.}
    glCheckFramebufferStatus: proc(target: uint32): uint32 {.cdecl.}
    glGenRenderbuffers: proc(count: int32; names: ptr uint32) {.cdecl.}
    glDeleteRenderbuffers: proc(count: int32; names: ptr uint32) {.cdecl.}
    glBindRenderbuffer: proc(target, name: uint32) {.cdecl.}
    glRenderbufferStorage: proc(target, format: uint32; width,height: int32) {.cdecl.}
    glFramebufferRenderbuffer: proc(target, attachment, renderbufferTarget, renderbuffer: uint32) {.cdecl.}
    glColorMask: proc(r,g,b,a: uint8) {.cdecl.}
    glUniform1f: proc(location: int32; value: float32) {.cdecl.}
    glUniform2f: proc(location: int32; x,y: float32) {.cdecl.}
    glBufferSubData: proc(target: uint32; offset, size: int; data: pointer) {.cdecl.}
    glDisableVertexAttribArray: proc(index: uint32) {.cdecl.}
    glVertexAttrib3f: proc(index: uint32; x,y,z: float32) {.cdecl.}
    glDepthMask: proc(flag: uint8) {.cdecl.}
    glDepthFunc: proc(value: uint32) {.cdecl.}
    glClearDepthf: proc(value: float32) {.cdecl.}
    glVertexAttribDivisor: proc(index, divisor: uint32) {.cdecl.}
    glDrawArraysInstanced: proc(mode: uint32; first,count,instances: int32) {.cdecl.}
    glDrawElementsInstanced: proc(mode: uint32; count: int32; kind: uint32; offset: pointer; instances: int32) {.cdecl.}
    glDrawElements: proc(mode: uint32; count: int32; kind: uint32; offset: pointer) {.cdecl.}
    glGenTextures: proc(count: int32; textures: ptr uint32) {.cdecl.}
    glDeleteTextures: proc(count: int32; textures: ptr uint32) {.cdecl.}
    glBindTexture: proc(target, texture: uint32) {.cdecl.}
    glActiveTexture: proc(unit: uint32) {.cdecl.}
    glTexParameteri: proc(target, name: uint32; value: int32) {.cdecl.}
    glPixelStorei: proc(name: uint32; value: int32) {.cdecl.}
    glTexImage2D: proc(target: uint32; level, internalFormat, width, height, border: int32; format, kind: uint32; data: pointer) {.cdecl.}
    glTexSubImage2D: proc(target: uint32; level, x,y,width,height: int32; format, kind: uint32; data: pointer) {.cdecl.}
    glGetIntegerv: proc(name: uint32; value: ptr int32) {.cdecl.}
    glUniform1i: proc(location, value: int32) {.cdecl.}
    glGetUniformLocation: proc(p: uint32; name: cstring): int32 {.cdecl.}
    glUniformMatrix4fv: proc(location, count: int32; transpose: uint8; data: ptr float32) {.cdecl.}
    glCreateShader: proc(kind: uint32): uint32 {.cdecl.}
    glShaderSource: proc(shader: uint32; count: int32; source: ptr cstring; lengths: ptr int32) {.cdecl.}
    glCompileShader: proc(shader: uint32) {.cdecl.}
    glGetShaderiv: proc(shader, name: uint32; value: ptr int32) {.cdecl.}
    glGetShaderInfoLog: proc(shader: uint32; size: int32; length: ptr int32; log: cstring) {.cdecl.}
    glDeleteShader: proc(shader: uint32) {.cdecl.}
    glCreateProgram: proc(): uint32 {.cdecl.}
    glAttachShader: proc(program, shader: uint32) {.cdecl.}
    glBindAttribLocation: proc(program, index: uint32; name: cstring) {.cdecl.}
    glLinkProgram: proc(program: uint32) {.cdecl.}
    glGetProgramiv: proc(program, name: uint32; value: ptr int32) {.cdecl.}
    glGetProgramInfoLog: proc(program: uint32; size: int32; length: ptr int32; log: cstring) {.cdecl.}
    glDeleteProgram: proc(program: uint32) {.cdecl.}
    glGenBuffers: proc(count: int32; buffers: ptr uint32) {.cdecl.}
    glBindBuffer: proc(target, buffer: uint32) {.cdecl.}
    glBufferData: proc(target: uint32; size: int; data: pointer; usage: uint32) {.cdecl.}
    glDeleteBuffers: proc(count: int32; buffers: ptr uint32) {.cdecl.}
    glViewport: proc(x,y,width,height: int32) {.cdecl.}
    glDisable: proc(cap: uint32) {.cdecl.}
    glEnable: proc(cap: uint32) {.cdecl.}
    glClearColor: proc(r,g,b,a: float32) {.cdecl.}
    glClear: proc(mask: uint32) {.cdecl.}
    glUseProgram: proc(program: uint32) {.cdecl.}
    glEnableVertexAttribArray: proc(index: uint32) {.cdecl.}
    glVertexAttribPointer: proc(index: uint32; size: int32; kind: uint32; normalized: uint8; stride: int32; offset: pointer) {.cdecl.}
    glDrawArrays: proc(mode: uint32; first,count: int32) {.cdecl.}

proc acquire*(resolve: Resolver): Context =
  if resolve == nil: raise newException(ValueError, "GLES resolver is nil")
  result.glUniform4f = cast[typeof(result.glUniform4f)](resolve("glUniform4f"))
  if result.glUniform4f == nil: raise newException(ValueError,"Missing GLES entry point: glUniform4f")
  result.glGenFramebuffers = cast[typeof(result.glGenFramebuffers)](resolve("glGenFramebuffers"))
  if result.glGenFramebuffers == nil: raise newException(ValueError,"Missing GLES entry point: glGenFramebuffers")
  result.glDeleteFramebuffers = cast[typeof(result.glDeleteFramebuffers)](resolve("glDeleteFramebuffers"))
  if result.glDeleteFramebuffers == nil: raise newException(ValueError,"Missing GLES entry point: glDeleteFramebuffers")
  result.glBindFramebuffer = cast[typeof(result.glBindFramebuffer)](resolve("glBindFramebuffer"))
  if result.glBindFramebuffer == nil: raise newException(ValueError,"Missing GLES entry point: glBindFramebuffer")
  result.glFramebufferTexture2D = cast[typeof(result.glFramebufferTexture2D)](resolve("glFramebufferTexture2D"))
  if result.glFramebufferTexture2D == nil: raise newException(ValueError,"Missing GLES entry point: glFramebufferTexture2D")
  result.glCheckFramebufferStatus = cast[typeof(result.glCheckFramebufferStatus)](resolve("glCheckFramebufferStatus"))
  if result.glCheckFramebufferStatus == nil: raise newException(ValueError,"Missing GLES entry point: glCheckFramebufferStatus")
  result.glGenRenderbuffers = cast[typeof(result.glGenRenderbuffers)](resolve("glGenRenderbuffers"))
  if result.glGenRenderbuffers == nil: raise newException(ValueError,"Missing GLES entry point: glGenRenderbuffers")
  result.glDeleteRenderbuffers = cast[typeof(result.glDeleteRenderbuffers)](resolve("glDeleteRenderbuffers"))
  if result.glDeleteRenderbuffers == nil: raise newException(ValueError,"Missing GLES entry point: glDeleteRenderbuffers")
  result.glBindRenderbuffer = cast[typeof(result.glBindRenderbuffer)](resolve("glBindRenderbuffer"))
  if result.glBindRenderbuffer == nil: raise newException(ValueError,"Missing GLES entry point: glBindRenderbuffer")
  result.glRenderbufferStorage = cast[typeof(result.glRenderbufferStorage)](resolve("glRenderbufferStorage"))
  if result.glRenderbufferStorage == nil: raise newException(ValueError,"Missing GLES entry point: glRenderbufferStorage")
  result.glFramebufferRenderbuffer = cast[typeof(result.glFramebufferRenderbuffer)](resolve("glFramebufferRenderbuffer"))
  if result.glFramebufferRenderbuffer == nil: raise newException(ValueError,"Missing GLES entry point: glFramebufferRenderbuffer")
  result.glColorMask = cast[typeof(result.glColorMask)](resolve("glColorMask"))
  if result.glColorMask == nil: raise newException(ValueError,"Missing GLES entry point: glColorMask")
  result.glUniform1f = cast[typeof(result.glUniform1f)](resolve("glUniform1f"))
  if result.glUniform1f == nil: raise newException(ValueError,"Missing GLES entry point: glUniform1f")
  result.glUniform2f = cast[typeof(result.glUniform2f)](resolve("glUniform2f"))
  if result.glUniform2f == nil: raise newException(ValueError,"Missing GLES entry point: glUniform2f")
  result.glBufferSubData = cast[typeof(result.glBufferSubData)](resolve("glBufferSubData"))
  if result.glBufferSubData == nil: raise newException(ValueError, "Missing GLES entry point: glBufferSubData")
  result.glDisableVertexAttribArray = cast[typeof(result.glDisableVertexAttribArray)](resolve("glDisableVertexAttribArray"))
  if result.glDisableVertexAttribArray == nil: raise newException(ValueError, "Missing GLES entry point: glDisableVertexAttribArray")
  result.glVertexAttrib3f = cast[typeof(result.glVertexAttrib3f)](resolve("glVertexAttrib3f"))
  if result.glVertexAttrib3f == nil: raise newException(ValueError, "Missing GLES entry point: glVertexAttrib3f")
  result.glDepthMask = cast[typeof(result.glDepthMask)](resolve("glDepthMask"))
  if result.glDepthMask == nil: raise newException(ValueError, "Missing GLES entry point: glDepthMask")
  result.glDepthFunc = cast[typeof(result.glDepthFunc)](resolve("glDepthFunc"))
  if result.glDepthFunc == nil: raise newException(ValueError, "Missing GLES entry point: glDepthFunc")
  result.glClearDepthf = cast[typeof(result.glClearDepthf)](resolve("glClearDepthf"))
  if result.glClearDepthf == nil: raise newException(ValueError, "Missing GLES entry point: glClearDepthf")
  result.glVertexAttribDivisor = cast[typeof(result.glVertexAttribDivisor)](resolve("glVertexAttribDivisor"))
  result.glDrawArraysInstanced = cast[typeof(result.glDrawArraysInstanced)](resolve("glDrawArraysInstanced"))
  result.glDrawElementsInstanced = cast[typeof(result.glDrawElementsInstanced)](resolve("glDrawElementsInstanced"))
  result.glDrawElements = cast[typeof(result.glDrawElements)](resolve("glDrawElements"))
  if result.glDrawElements == nil: raise newException(ValueError, "Missing GLES entry point: glDrawElements")
  result.glGenTextures = cast[typeof(result.glGenTextures)](resolve("glGenTextures"))
  if result.glGenTextures == nil: raise newException(ValueError, "Missing GLES entry point: glGenTextures")
  result.glDeleteTextures = cast[typeof(result.glDeleteTextures)](resolve("glDeleteTextures"))
  if result.glDeleteTextures == nil: raise newException(ValueError, "Missing GLES entry point: glDeleteTextures")
  result.glBindTexture = cast[typeof(result.glBindTexture)](resolve("glBindTexture"))
  if result.glBindTexture == nil: raise newException(ValueError, "Missing GLES entry point: glBindTexture")
  result.glActiveTexture = cast[typeof(result.glActiveTexture)](resolve("glActiveTexture"))
  if result.glActiveTexture == nil: raise newException(ValueError, "Missing GLES entry point: glActiveTexture")
  result.glTexParameteri = cast[typeof(result.glTexParameteri)](resolve("glTexParameteri"))
  if result.glTexParameteri == nil: raise newException(ValueError, "Missing GLES entry point: glTexParameteri")
  result.glPixelStorei = cast[typeof(result.glPixelStorei)](resolve("glPixelStorei"))
  if result.glPixelStorei == nil: raise newException(ValueError, "Missing GLES entry point: glPixelStorei")
  result.glTexImage2D = cast[typeof(result.glTexImage2D)](resolve("glTexImage2D"))
  if result.glTexImage2D == nil: raise newException(ValueError, "Missing GLES entry point: glTexImage2D")
  result.glTexSubImage2D = cast[typeof(result.glTexSubImage2D)](resolve("glTexSubImage2D"))
  if result.glTexSubImage2D == nil: raise newException(ValueError, "Missing GLES entry point: glTexSubImage2D")
  result.glGetIntegerv = cast[typeof(result.glGetIntegerv)](resolve("glGetIntegerv"))
  if result.glGetIntegerv == nil: raise newException(ValueError, "Missing GLES entry point: glGetIntegerv")
  result.glUniform1i = cast[typeof(result.glUniform1i)](resolve("glUniform1i"))
  if result.glUniform1i == nil: raise newException(ValueError, "Missing GLES entry point: glUniform1i")
  result.glGetUniformLocation = cast[typeof(result.glGetUniformLocation)](resolve("glGetUniformLocation"))
  result.glUniformMatrix4fv = cast[typeof(result.glUniformMatrix4fv)](resolve("glUniformMatrix4fv"))
  if result.glGetUniformLocation == nil or result.glUniformMatrix4fv == nil:
    raise newException(ValueError, "Missing GLES uniform entry points")
  result.glCreateShader = cast[typeof(result.glCreateShader)](resolve("glCreateShader"))
  if result.glCreateShader == nil: raise newException(ValueError, "Missing GLES entry point: glCreateShader")
  result.glShaderSource = cast[typeof(result.glShaderSource)](resolve("glShaderSource"))
  if result.glShaderSource == nil: raise newException(ValueError, "Missing GLES entry point: glShaderSource")
  result.glCompileShader = cast[typeof(result.glCompileShader)](resolve("glCompileShader"))
  if result.glCompileShader == nil: raise newException(ValueError, "Missing GLES entry point: glCompileShader")
  result.glGetShaderiv = cast[typeof(result.glGetShaderiv)](resolve("glGetShaderiv"))
  if result.glGetShaderiv == nil: raise newException(ValueError, "Missing GLES entry point: glGetShaderiv")
  result.glGetShaderInfoLog = cast[typeof(result.glGetShaderInfoLog)](resolve("glGetShaderInfoLog"))
  if result.glGetShaderInfoLog == nil: raise newException(ValueError, "Missing GLES entry point: glGetShaderInfoLog")
  result.glDeleteShader = cast[typeof(result.glDeleteShader)](resolve("glDeleteShader"))
  if result.glDeleteShader == nil: raise newException(ValueError, "Missing GLES entry point: glDeleteShader")
  result.glCreateProgram = cast[typeof(result.glCreateProgram)](resolve("glCreateProgram"))
  if result.glCreateProgram == nil: raise newException(ValueError, "Missing GLES entry point: glCreateProgram")
  result.glAttachShader = cast[typeof(result.glAttachShader)](resolve("glAttachShader"))
  if result.glAttachShader == nil: raise newException(ValueError, "Missing GLES entry point: glAttachShader")
  result.glBindAttribLocation = cast[typeof(result.glBindAttribLocation)](resolve("glBindAttribLocation"))
  if result.glBindAttribLocation == nil: raise newException(ValueError, "Missing GLES entry point: glBindAttribLocation")
  result.glLinkProgram = cast[typeof(result.glLinkProgram)](resolve("glLinkProgram"))
  if result.glLinkProgram == nil: raise newException(ValueError, "Missing GLES entry point: glLinkProgram")
  result.glGetProgramiv = cast[typeof(result.glGetProgramiv)](resolve("glGetProgramiv"))
  if result.glGetProgramiv == nil: raise newException(ValueError, "Missing GLES entry point: glGetProgramiv")
  result.glGetProgramInfoLog = cast[typeof(result.glGetProgramInfoLog)](resolve("glGetProgramInfoLog"))
  if result.glGetProgramInfoLog == nil: raise newException(ValueError, "Missing GLES entry point: glGetProgramInfoLog")
  result.glDeleteProgram = cast[typeof(result.glDeleteProgram)](resolve("glDeleteProgram"))
  if result.glDeleteProgram == nil: raise newException(ValueError, "Missing GLES entry point: glDeleteProgram")
  result.glGenBuffers = cast[typeof(result.glGenBuffers)](resolve("glGenBuffers"))
  if result.glGenBuffers == nil: raise newException(ValueError, "Missing GLES entry point: glGenBuffers")
  result.glBindBuffer = cast[typeof(result.glBindBuffer)](resolve("glBindBuffer"))
  if result.glBindBuffer == nil: raise newException(ValueError, "Missing GLES entry point: glBindBuffer")
  result.glBufferData = cast[typeof(result.glBufferData)](resolve("glBufferData"))
  if result.glBufferData == nil: raise newException(ValueError, "Missing GLES entry point: glBufferData")
  result.glDeleteBuffers = cast[typeof(result.glDeleteBuffers)](resolve("glDeleteBuffers"))
  if result.glDeleteBuffers == nil: raise newException(ValueError, "Missing GLES entry point: glDeleteBuffers")
  result.glViewport = cast[typeof(result.glViewport)](resolve("glViewport"))
  if result.glViewport == nil: raise newException(ValueError, "Missing GLES entry point: glViewport")
  result.glDisable = cast[typeof(result.glDisable)](resolve("glDisable"))
  if result.glDisable == nil: raise newException(ValueError, "Missing GLES entry point: glDisable")
  result.glEnable = cast[typeof(result.glEnable)](resolve("glEnable"))
  if result.glEnable == nil: raise newException(ValueError, "Missing GLES entry point: glEnable")
  result.glClearColor = cast[typeof(result.glClearColor)](resolve("glClearColor"))
  if result.glClearColor == nil: raise newException(ValueError, "Missing GLES entry point: glClearColor")
  result.glClear = cast[typeof(result.glClear)](resolve("glClear"))
  if result.glClear == nil: raise newException(ValueError, "Missing GLES entry point: glClear")
  result.glUseProgram = cast[typeof(result.glUseProgram)](resolve("glUseProgram"))
  if result.glUseProgram == nil: raise newException(ValueError, "Missing GLES entry point: glUseProgram")
  result.glEnableVertexAttribArray = cast[typeof(result.glEnableVertexAttribArray)](resolve("glEnableVertexAttribArray"))
  if result.glEnableVertexAttribArray == nil: raise newException(ValueError, "Missing GLES entry point: glEnableVertexAttribArray")
  result.glVertexAttribPointer = cast[typeof(result.glVertexAttribPointer)](resolve("glVertexAttribPointer"))
  if result.glVertexAttribPointer == nil: raise newException(ValueError, "Missing GLES entry point: glVertexAttribPointer")
  result.glDrawArrays = cast[typeof(result.glDrawArrays)](resolve("glDrawArrays"))
  if result.glDrawArrays == nil: raise newException(ValueError, "Missing GLES entry point: glDrawArrays")


proc compile(gl: Context; kind: uint32; source: string): uint32 =
  result = gl.glCreateShader(kind)
  var s = cstring(source)
  gl.glShaderSource(result, 1, addr s, nil)
  gl.glCompileShader(result)
  var ok: int32
  gl.glGetShaderiv(result, 0x8B81, addr ok)
  if ok == 0:
    var log = newString(4096)
    gl.glGetShaderInfoLog(result, 4096, nil, cstring(log))
    gl.glDeleteShader(result)
    raise newException(ValueError, log)

proc createProgram*(gl: Context; vs, fs: string): Program =
  let v = compile(gl, 0x8B31, vs)
  var f: uint32
  try:
    f = compile(gl, 0x8B30, fs)
    result = gl.glCreateProgram()
    gl.glAttachShader(result, v)
    gl.glAttachShader(result, f)
    gl.glBindAttribLocation(result, 0, "aPosition")
    gl.glBindAttribLocation(result, 1, "aNormal")
    gl.glBindAttribLocation(result, 2, "aColor")
    gl.glBindAttribLocation(result, 3, "aTerritory")
    gl.glBindAttribLocation(result, 4, "aInstancePosition")
    gl.glBindAttribLocation(result, 5, "aInstanceRotationScale")
    gl.glBindAttribLocation(result, 6, "aInstanceTint")
    gl.glLinkProgram(result)
    var ok: int32
    gl.glGetProgramiv(result, 0x8B82, addr ok)
    if ok == 0:
      var log = newString(4096)
      gl.glGetProgramInfoLog(result, 4096, nil, cstring(log))
      gl.glDeleteProgram(result)
      raise newException(ValueError, log)
  finally:
    gl.glDeleteShader(v)
    if f != 0: gl.glDeleteShader(f)

proc createBuffer*(gl: Context; data: seq[float32]): Buffer =
  gl.glGenBuffers(1, addr result)
  gl.glBindBuffer(0x8892, result)
  gl.glBufferData(0x8892, data.len * 4, unsafeAddr data[0], 0x88E4)

proc createIndices*(gl: Context; data: seq[uint16]): Buffer =
  if data.len == 0: return
  gl.glGenBuffers(1,addr result)
  gl.glBindBuffer(0x8893,result)
  gl.glBufferData(0x8893,data.len*2,unsafeAddr data[0],0x88E4)

proc texture(gl: Context; unit: uint32): uint32 =
  gl.glGenTextures(1,addr result)
  gl.glActiveTexture(unit)
  gl.glBindTexture(0x0DE1,result)
  for name in [0x2800'u32,0x2801]: gl.glTexParameteri(0x0DE1,name,0x2600)
  for name in [0x2802'u32,0x2803]: gl.glTexParameteri(0x0DE1,name,0x812F)

proc createTerritory*(gl: Context; p: Program; modern: bool; m: OwnerMap): TerritoryBinding =
  var limit: int32
  gl.glGetIntegerv(0x0D33,addr limit)
  if m.width > limit or m.height > limit or limit < 256:
    raise newException(ValueError, "Owner map exceeds MAX_TEXTURE_SIZE")
  result.modern = modern
  result.owners = texture(gl,0x84C0)
  let pixels = m.pixels
  let palette = m.palette
  gl.glPixelStorei(0x0CF5,1)
  gl.glTexImage2D(0x0DE1,0,(if modern: 0x8229 else: 0x1909),int32(m.width),int32(m.height),0,
    (if modern: 0x1903'u32 else: 0x1909'u32),0x1401,unsafeAddr pixels[0])
  result.palette = texture(gl,0x84C1)
  gl.glTexImage2D(0x0DE1,0,0x1908,256,1,0,0x1908,0x1401,unsafeAddr palette[0])
  gl.glPixelStorei(0x0CF5,4)
  gl.glUseProgram(p)
  gl.glUniform1i(gl.glGetUniformLocation(p,"uOwners"),0)
  gl.glUniform1i(gl.glGetUniformLocation(p,"uPalette"),1)

proc uploadDelta*(gl: Context; t: TerritoryBinding; x,y,w,h: int; data: seq[uint8]) =
  gl.glActiveTexture(0x84C0)
  gl.glBindTexture(0x0DE1,t.owners)
  gl.glPixelStorei(0x0CF5,1)
  gl.glTexSubImage2D(0x0DE1,0,int32(x),int32(y),int32(w),int32(h),
    (if t.modern: 0x1903'u32 else: 0x1909'u32),0x1401,unsafeAddr data[0])
  gl.glPixelStorei(0x0CF5,4)

proc destroyTerritory*(gl: Context; t: TerritoryBinding) =
  var ids = [t.owners,t.palette]
  gl.glDeleteTextures(2,addr ids[0])

proc matrixBinding*(gl: Context; p: Program): MatrixBinding =
  gl.glGetUniformLocation(p, "uViewProjection")

proc createInstanceStream*(gl: Context; api: Api; capacity: int; forceFallback: bool): InstanceStream =
  if api == gles3 and not forceFallback:
    if gl.glVertexAttribDivisor == nil or gl.glDrawArraysInstanced == nil or gl.glDrawElementsInstanced == nil:
      raise newException(ValueError, "GLES3 instancing entry points missing")
    result.mode = coreInstancing
    gl.glGenBuffers(1,addr result.buffer)
    gl.glBindBuffer(0x8892,result.buffer)
    gl.glBufferData(0x8892,capacity*InstanceBytes,nil,0x88E8)

proc uploadInstances*(gl: Context; stream: var InstanceStream; data: seq[float32]; count: int) =
  if stream.mode == fallbackDraws or count == 0: return
  gl.glBindBuffer(0x8892,stream.buffer)
  gl.glBufferSubData(0x8892,0,count*InstanceBytes,unsafeAddr data[0])

proc destroyInstanceStream*(gl: Context; stream: InstanceStream) =
  var id = stream.buffer
  gl.glDeleteBuffers(1,addr id)

proc identityInstance(gl: Context) =
  for i in 4'u32..6'u32: gl.glDisableVertexAttribArray(i)
  gl.glVertexAttrib3f(4,0,0,0)
  gl.glVertexAttrib3f(5,1,0,1)
  gl.glVertexAttrib3f(6,1,1,1)

proc prepare(gl: Context; p: Program; b: Buffer; count, width, height: int; binding: MatrixBinding; matrix: Mat4; indices: Buffer; indexed: bool; territory: TerritoryBinding; clear: bool) =
  gl.glViewport(0, 0, int32(width), int32(height))
  gl.glDisable(0x0BE2)
  gl.glDisable(0x0C11)
  gl.glEnable(0x0B71)
  gl.glDepthMask(1)
  gl.glDepthFunc(0x0201)
  if clear:
    gl.glClearDepthf(1)
    gl.glClearColor(0.65, 0.74, 0.82, 1)
    gl.glClear(0x4100)
  gl.glUseProgram(p)
  gl.glUniformMatrix4fv(binding, 1, 0, unsafeAddr matrix[0])
  gl.glActiveTexture(0x84C0)
  gl.glBindTexture(0x0DE1,territory.owners)
  gl.glActiveTexture(0x84C1)
  gl.glBindTexture(0x0DE1,territory.palette)
  gl.glBindBuffer(0x8892, b)
  for i in 0..3:
    gl.glEnableVertexAttribArray(uint32(i))
    gl.glVertexAttribPointer(uint32(i), 3, 0x1406, 0, 48, cast[pointer](i*12))

proc drawGeometry(gl: Context; count: int; indices: Buffer; indexed: bool) =
  if indexed:
    gl.glBindBuffer(0x8893,indices)
    gl.glDrawElements(0x0004,int32(count),0x1403,nil)
  else: gl.glDrawArrays(0x0004,0,int32(count))

proc draw*(gl: Context; p: Program; b: Buffer; count, width, height: int; binding: MatrixBinding; matrix: Mat4; indices: Buffer; indexed: bool; territory: TerritoryBinding; clear: bool; background = false) =
  prepare(gl,p,b,count,width,height,binding,matrix,indices,indexed,territory,clear)
  if background:
    gl.glDisable(0x0B71)
    gl.glDepthMask(0)
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
        gl.glVertexAttrib3f(uint32(4+attribute),data[i],data[i+1],data[i+2])
      drawGeometry(gl,count,indices,indexed)
  else:
    gl.glBindBuffer(0x8892,stream.buffer)
    for i in 0..2:
      gl.glEnableVertexAttribArray(uint32(4+i))
      gl.glVertexAttribPointer(uint32(4+i),3,0x1406,0,InstanceBytes,cast[pointer](i*12))
      gl.glVertexAttribDivisor(uint32(4+i),1)
    if indexed:
      gl.glBindBuffer(0x8893,indices)
      gl.glDrawElementsInstanced(0x0004,int32(count),0x1403,nil,int32(instances))
    else: gl.glDrawArraysInstanced(0x0004,0,int32(count),int32(instances))
    for i in 4'u32..6'u32: gl.glVertexAttribDivisor(i,0)
  identityInstance(gl)

proc destroy*(gl: Context; p: Program; b: Buffer) =
  gl.glDeleteProgram(p)
  var buffer = b
  gl.glDeleteBuffers(1, addr buffer)

proc destroyIndices*(gl: Context; b: Buffer) =
  var id = b
  gl.glDeleteBuffers(1,addr id)

include post_gles

type EffectBinding* = object
  fog, eye, color: int32
  rects, planes: array[MaxBlobs,int32]

proc effectBinding*(gl: Context; p: Program): EffectBinding =
  result.fog = gl.glGetUniformLocation(p,"uFog")
  result.eye = gl.glGetUniformLocation(p,"uEye")
  result.color = gl.glGetUniformLocation(p,"uFogColor")
  for i in 0..<MaxBlobs:
    result.rects[i] = gl.glGetUniformLocation(p,cstring("uBlobRects[" & $i & "]"))
    result.planes[i] = gl.glGetUniformLocation(p,cstring("uBlobPlanes[" & $i & "]"))

proc updateEffects*(gl: Context; p: Program; b: EffectBinding; s: SceneEffects;
                    changes: EffectChanges): int =
  gl.glUseProgram(p)
  if changes.parameters:
    gl.glUniform4f(b.fog,(if s.fogEnabled: s.fogNear else: 0'f32),
      (if s.fogEnabled: 1'f32/(s.fogFar-s.fogNear) else: 0'f32),float32(s.blobCount),0)
    inc result
  if changes.eye:
    if s.fogEnabled: gl.glUniform4f(b.eye,s.eye[0],s.eye[1],s.eye[2],0)
    else: gl.glUniform4f(b.eye,0,0,0,0)
    inc result
  if changes.color:
    if s.fogEnabled: gl.glUniform4f(b.color,s.fogColor[0],s.fogColor[1],s.fogColor[2],0)
    else: gl.glUniform4f(b.color,0,0,0,0)
    inc result
  for i in 0..<MaxBlobs:
    if changes.blobs[i]:
      if i < s.blobCount:
        template blob: untyped = s.blobs[i]
        gl.glUniform4f(b.rects[i],blob.center[0],blob.center[2],blob.radiusX,blob.radiusZ)
        gl.glUniform4f(b.planes[i],blob.center[1],blob.strength,cos(blob.yaw),sin(blob.yaw))
      else:
        gl.glUniform4f(b.rects[i],0,0,0,0)
        gl.glUniform4f(b.planes[i],0,0,0,0)
      result += 2
