# Included by gles.nim. All additional entry points are GLES2 core.
import ../[post_types, post_shaders]
type
  PostTarget* = object
    framebuffer, color, depth: uint32
  PostPass* = object
    program: Program
    buffer: Buffer
    invSize, fxaa, dither, exposure, vignette: int32

proc targetLimit*(gl: Context): int =
  var texture, renderbuffer: int32
  gl.glGetIntegerv(0x0D33,addr texture)
  gl.glGetIntegerv(0x84E8,addr renderbuffer)
  int(min(texture,renderbuffer))

proc defaultTarget*(gl: Context) = gl.glBindFramebuffer(0x8D40,0)

proc destroyTarget*(gl: Context; t: var PostTarget) =
  if t.framebuffer != 0: gl.glDeleteFramebuffers(1,addr t.framebuffer)
  if t.color != 0: gl.glDeleteTextures(1,addr t.color)
  if t.depth != 0: gl.glDeleteRenderbuffers(1,addr t.depth)
  t = default(PostTarget)

proc createTarget*(gl: Context; w,h: int): PostTarget =
  try:
    gl.glGenFramebuffers(1,addr result.framebuffer)
    gl.glGenTextures(1,addr result.color)
    gl.glGenRenderbuffers(1,addr result.depth)
    if result.framebuffer == 0 or result.color == 0 or result.depth == 0:
      raise newException(ValueError,"Cannot allocate post target")
    gl.glActiveTexture(0x84C0)
    gl.glBindTexture(0x0DE1,result.color)
    for name in [0x2800'u32,0x2801]: gl.glTexParameteri(0x0DE1,name,0x2601)
    for name in [0x2802'u32,0x2803]: gl.glTexParameteri(0x0DE1,name,0x812F)
    gl.glTexImage2D(0x0DE1,0,0x8058,int32(w),int32(h),0,0x1908,0x1401,nil)
    gl.glBindRenderbuffer(0x8D41,result.depth)
    gl.glRenderbufferStorage(0x8D41,0x81A5,int32(w),int32(h))
    gl.glBindFramebuffer(0x8D40,result.framebuffer)
    gl.glFramebufferTexture2D(0x8D40,0x8CE0,0x0DE1,result.color,0)
    gl.glFramebufferRenderbuffer(0x8D40,0x8D00,0x8D41,result.depth)
    if gl.glCheckFramebufferStatus(0x8D40) != 0x8CD5:
      raise newException(ValueError,"Incomplete post framebuffer")
  except:
    gl.destroyTarget(result)
    raise
  finally:
    gl.defaultTarget()
    gl.glBindRenderbuffer(0x8D41,0)
    gl.glBindTexture(0x0DE1,0)

proc destroyPost*(gl: Context; p: var PostPass) =
  if p.program != 0: gl.glDeleteProgram(p.program)
  if p.buffer != 0: gl.glDeleteBuffers(1,addr p.buffer)
  p = default(PostPass)

proc createPost*(gl: Context): PostPass =
  try:
    result.program = gl.createProgram(PostVertex,PostFragment)
    result.buffer = gl.createBuffer(@[-1'f32,-1,0, 3,-1,0, -1,3,0])
    if result.buffer == 0: raise newException(ValueError,"Cannot allocate post triangle")
    result.invSize = gl.glGetUniformLocation(result.program,"uInvSize")
    result.fxaa = gl.glGetUniformLocation(result.program,"uFxaa")
    result.dither = gl.glGetUniformLocation(result.program,"uDither")
    result.exposure = gl.glGetUniformLocation(result.program,"uExposure")
    result.vignette = gl.glGetUniformLocation(result.program,"uVignette")
    gl.glUseProgram(result.program)
    gl.glUniform1i(gl.glGetUniformLocation(result.program,"uScene"),0)
  except:
    gl.destroyPost(result)
    raise

proc beginTarget*(gl: Context; t: PostTarget; offscreen: bool; w,h: int) =
  gl.glBindFramebuffer(0x8D40,if offscreen: t.framebuffer else: 0)
  gl.glViewport(0,0,int32(w),int32(h))
  gl.glDisable(0x0C11)
  gl.glColorMask(1,1,1,1)
  gl.glDepthMask(1)
  gl.glClearDepthf(1)
  gl.glClearColor(0.65,0.74,0.82,1)
  gl.glClear(0x4000 or 0x0100)

proc present*(gl: Context; p: PostPass; t: PostTarget; w,h,rw,rh: int; s: PostSettings) =
  gl.defaultTarget()
  gl.glViewport(0,0,int32(w),int32(h))
  for cap in [0x0B71'u32,0x0BE2,0x0B44,0x0C11]: gl.glDisable(cap)
  gl.glColorMask(1,1,1,1)
  gl.glUseProgram(p.program)
  gl.glActiveTexture(0x84C0)
  gl.glBindTexture(0x0DE1,t.color)
  gl.glUniform2f(p.invSize,1'f32/float32(rw),1'f32/float32(rh))
  gl.glUniform1i(p.fxaa,int32(ord(s.fxaa)))
  gl.glUniform1i(p.dither,int32(ord(s.dither)))
  gl.glUniform1f(p.exposure,s.exposure)
  gl.glUniform1f(p.vignette,s.vignette)
  for i in 0'u32..6:
    gl.glVertexAttribDivisor(i,0)
    if i > 0: gl.glDisableVertexAttribArray(i)
  gl.glBindBuffer(0x8892,p.buffer)
  gl.glEnableVertexAttribArray(0)
  gl.glVertexAttribPointer(0,3,0x1406,0,12,nil)
  gl.glDrawArrays(0x0004,0,3)
  gl.glBindTexture(0x0DE1,0)
