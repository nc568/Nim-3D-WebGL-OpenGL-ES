# Included by web.nim; private GL-family details, not part of the facade.
import ../[post_types, post_shaders]
type
  PostTarget* = object
    framebuffer, color, depth: JsObject
  PostPass* = object
    program: Program
    buffer: Buffer
    invSize, fxaa, dither, exposure, vignette: JsObject

proc targetLimit*(gl: Context): int =
  min(gl.getParameter(0x0D33).to(int),gl.getParameter(0x84E8).to(int))

proc defaultTarget*(gl: Context) = gl.bindFramebuffer(0x8D40,nil)

proc destroyTarget*(gl: Context; t: var PostTarget) =
  if not t.framebuffer.isNil: gl.deleteFramebuffer(t.framebuffer)
  if not t.color.isNil: gl.deleteTexture(t.color)
  if not t.depth.isNil: gl.deleteRenderbuffer(t.depth)
  t = default(PostTarget)

proc createTarget*(gl: Context; w,h: int): PostTarget =
  try:
    result.framebuffer = gl.createFramebuffer()
    result.color = gl.createTexture()
    result.depth = gl.createRenderbuffer()
    if result.framebuffer.isNil or result.color.isNil or result.depth.isNil:
      raise newException(ValueError,"Cannot allocate post target")
    gl.activeTexture(0x84C0)
    gl.bindTexture(0x0DE1,result.color)
    for name in [0x2800,0x2801]: gl.texParameteri(0x0DE1,name,0x2601)
    for name in [0x2802,0x2803]: gl.texParameteri(0x0DE1,name,0x812F)
    gl.texImage2D(0x0DE1,0,0x8058,w,h,0,0x1908,0x1401,nil)
    gl.bindRenderbuffer(0x8D41,result.depth)
    gl.renderbufferStorage(0x8D41,0x81A5,w,h)
    gl.bindFramebuffer(0x8D40,result.framebuffer)
    gl.framebufferTexture2D(0x8D40,0x8CE0,0x0DE1,result.color,0)
    gl.framebufferRenderbuffer(0x8D40,0x8D00,0x8D41,result.depth)
    if gl.checkFramebufferStatus(0x8D40).to(int) != 0x8CD5:
      raise newException(ValueError,"Incomplete post framebuffer")
  except:
    gl.destroyTarget(result)
    raise
  finally:
    gl.defaultTarget()
    gl.bindRenderbuffer(0x8D41,nil)
    gl.bindTexture(0x0DE1,nil)
  return

proc destroyPost*(gl: Context; p: var PostPass) =
  if not p.program.isNil: gl.deleteProgram(p.program)
  if not p.buffer.isNil: gl.deleteBuffer(p.buffer)
  p = default(PostPass)

proc createPost*(gl: Context): PostPass =
  try:
    result.program = gl.createProgram(PostVertex,PostFragment)
    result.buffer = gl.createBuffer(@[-1'f32,-1,0, 3,-1,0, -1,3,0])
    if result.buffer.isNil: raise newException(ValueError,"Cannot allocate post triangle")
    result.invSize = gl.getUniformLocation(result.program,"uInvSize")
    result.fxaa = gl.getUniformLocation(result.program,"uFxaa")
    result.dither = gl.getUniformLocation(result.program,"uDither")
    result.exposure = gl.getUniformLocation(result.program,"uExposure")
    result.vignette = gl.getUniformLocation(result.program,"uVignette")
    gl.useProgram(result.program)
    gl.uniform1i(gl.getUniformLocation(result.program,"uScene"),0)
  except:
    gl.destroyPost(result)
    raise
  return

proc beginTarget*(gl: Context; t: PostTarget; offscreen: bool; w,h: int) =
  gl.bindFramebuffer(0x8D40,if offscreen: t.framebuffer else: nil)
  gl.viewport(0,0,w,h)
  gl.disable(0x0C11) # scissor
  gl.colorMask(true,true,true,true)
  gl.depthMask(true)
  gl.clearDepth(1)
  gl.clearColor(0.65,0.74,0.82,1)
  gl.clear(0x4000 or 0x0100)

proc present*(gl: Context; p: PostPass; t: PostTarget; w,h,rw,rh: int; s: PostSettings) =
  gl.defaultTarget() # detach before sampling: never a feedback loop
  gl.viewport(0,0,w,h)
  for cap in [0x0B71,0x0BE2,0x0B44,0x0C11]: gl.disable(cap)
  gl.colorMask(true,true,true,true)
  gl.useProgram(p.program)
  gl.activeTexture(0x84C0)
  gl.bindTexture(0x0DE1,t.color)
  gl.uniform2f(p.invSize,1.0/float(rw),1.0/float(rh))
  gl.uniform1i(p.fxaa,ord(s.fxaa))
  gl.uniform1i(p.dither,ord(s.dither))
  gl.uniform1f(p.exposure,s.exposure)
  gl.uniform1f(p.vignette,s.vignette)
  for i in 0..6:
    gl.vertexAttribDivisor(i,0)
    if i > 0: gl.disableVertexAttribArray(i)
  gl.bindBuffer(0x8892,p.buffer)
  gl.enableVertexAttribArray(0)
  gl.vertexAttribPointer(0,3,0x1406,false,12,0)
  gl.drawArrays(0x0004,0,3)
  gl.bindTexture(0x0DE1,nil)
