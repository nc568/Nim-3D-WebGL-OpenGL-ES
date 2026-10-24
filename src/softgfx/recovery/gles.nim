## Resolve only advertised GLES robustness APIs. Do not infer support from pointer alone.
import std/strutils
import ../recovery
import ../backends/gles

type ResetProbe* = object
  check*: ResetCheck
  robustAccess*: bool
  source*: string
  notificationStrategy*: uint32 # 0=unknown; GL_LOSE_CONTEXT_ON_RESET=0x8252

proc resetProbe*(resolve: Resolver): ResetProbe =
  if resolve == nil: raise newException(ValueError,"Missing GLES resolver")
  result.source = "unavailable"
  let getString = cast[proc(name:uint32):cstring {.cdecl.}](resolve("glGetString"))
  let getInteger = cast[proc(name:uint32; value:ptr int32) {.cdecl.}](resolve("glGetIntegerv"))
  if getString == nil or getInteger == nil: return
  let raw = getString(0x1F03)
  if raw == nil: return
  let extensions = " " & $raw & " "
  var address: pointer
  if extensions.contains(" GL_KHR_robustness "):
    address = resolve("glGetGraphicsResetStatusKHR")
    result.source = "GL_KHR_robustness"
  elif extensions.contains(" GL_EXT_robustness "):
    address = resolve("glGetGraphicsResetStatusEXT")
    result.source = "GL_EXT_robustness"
  else:
    let version = getString(0x1F02)
    if version != nil and ($version).startsWith("OpenGL ES 3.2"):
      address = resolve("glGetGraphicsResetStatus")
      result.source = "GLES_3_2_core"
  if address == nil:
    result.source = "unavailable"
    return
  let status = cast[proc():uint32 {.cdecl.}](address)
  var strategy: int32
  getInteger(0x8256,addr strategy)
  result.notificationStrategy = cast[uint32](strategy)
  var access: int32
  getInteger(0x90F3,addr access)
  result.robustAccess = access != 0
  result.check = proc(): uint32 = status()
