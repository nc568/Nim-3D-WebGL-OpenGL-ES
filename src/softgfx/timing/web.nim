## WebGL timer extensions are optional (privacy/driver policy may disable them).
import std/jsffi
import ../timing

proc timerDriver*(gl: JsObject; modern: bool): TimerDriver =
  let ext = gl.getExtension(if modern: cstring("EXT_disjoint_timer_query_webgl2")
                           else: cstring("EXT_disjoint_timer_query"))
  if ext.isNil: return
  let bits = if modern: gl.getQuery(0x88BF,0x8864).to(int)
             else: ext.getQueryEXT(0x88BF,0x8864).to(int)
  if bits <= 0: return
  var queries: array[TimerSlots,JsObject]
  result.supported = true
  result.create = proc(slot: int): bool =
    queries[slot] = if modern: gl.createQuery() else: ext.createQueryEXT()
    not queries[slot].isNil
  result.destroy = proc(slot: int) =
    if modern: gl.deleteQuery(queries[slot])
    else: ext.deleteQueryEXT(queries[slot])
    queries[slot] = nil
  result.beginQuery = proc(slot: int) =
    if modern: gl.beginQuery(0x88BF,queries[slot])
    else: ext.beginQueryEXT(0x88BF,queries[slot])
  result.endQuery = proc() =
    if modern: gl.endQuery(0x88BF)
    else: ext.endQueryEXT(0x88BF)
  result.available = proc(slot: int): bool =
    if modern: gl.getQueryParameter(queries[slot],0x8867).to(bool)
    else: ext.getQueryObjectEXT(queries[slot],0x8867).to(bool)
  result.milliseconds = proc(slot: int): float64 =
    # JS Number, never to(int): nanosecond results can exceed signed int32.
    let ns = if modern: gl.getQueryParameter(queries[slot],0x8866).to(float64)
             else: ext.getQueryObjectEXT(queries[slot],0x8866).to(float64)
    ns/1_000_000.0
  result.disjoint = proc(): bool = gl.getParameter(0x8FBB).to(bool)
  result.lost = proc(): bool = gl.isContextLost().to(bool)
