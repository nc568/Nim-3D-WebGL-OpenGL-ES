## GLES EXT_disjoint_timer_query, optional even on GLES3. Resolve once; never
## infer support from non-null entry points alone. Host owns context loss signals.
import std/strutils
import ../timing
import ../backends/gles

proc timerDriver*(resolve: Resolver; contextLost: proc(): bool {.closure.}): TimerDriver =
  if resolve == nil or contextLost == nil:
    raise newException(ValueError,"Timer requires resolver and context-loss callback")
  let getString = cast[proc(name: uint32): cstring {.cdecl.}](resolve("glGetString"))
  if getString == nil or contextLost(): return
  let extensions = getString(0x1F03)
  if extensions == nil or not (" " & $extensions & " ").contains(" GL_EXT_disjoint_timer_query "): return
  let gen = cast[proc(n: int32; ids: ptr uint32) {.cdecl.}](resolve("glGenQueriesEXT"))
  let delete = cast[proc(n: int32; ids: ptr uint32) {.cdecl.}](resolve("glDeleteQueriesEXT"))
  let begin = cast[proc(target, id: uint32) {.cdecl.}](resolve("glBeginQueryEXT"))
  let finish = cast[proc(target: uint32) {.cdecl.}](resolve("glEndQueryEXT"))
  let get32 = cast[proc(id,name: uint32; value: ptr uint32) {.cdecl.}](resolve("glGetQueryObjectuivEXT"))
  let get64 = cast[proc(id,name: uint32; value: ptr uint64) {.cdecl.}](resolve("glGetQueryObjectui64vEXT"))
  let integer = cast[proc(name: uint32; value: ptr int32) {.cdecl.}](resolve("glGetIntegerv"))
  let queryInfo = cast[proc(target,name: uint32; value: ptr int32) {.cdecl.}](resolve("glGetQueryivEXT"))
  if gen == nil or delete == nil or begin == nil or finish == nil or get32 == nil or
      get64 == nil or integer == nil or queryInfo == nil: return
  var bits: int32
  queryInfo(0x88BF,0x8864,addr bits)
  if bits <= 0: return
  var queries: array[TimerSlots,uint32]
  result.supported = true
  result.create = proc(slot: int): bool =
    gen(1,addr queries[slot])
    queries[slot] != 0
  result.destroy = proc(slot: int) =
    delete(1,addr queries[slot])
    queries[slot] = 0
  result.beginQuery = proc(slot: int) = begin(0x88BF,queries[slot])
  result.endQuery = proc() = finish(0x88BF)
  result.available = proc(slot: int): bool =
    var value: uint32
    get32(queries[slot],0x8867,addr value)
    value != 0
  result.milliseconds = proc(slot: int): float64 =
    var value: uint64
    get64(queries[slot],0x8866,addr value)
    float64(value)/1_000_000.0
  result.disjoint = proc(): bool =
    var value: int32
    integer(0x8FBB,addr value)
    value != 0
  result.lost = contextLost
