import softgfx/[recovery, scopes]
var calls = 0
var code = 0'u32
let contextGuard = newContextScopes()
let check: ResetCheck = proc():uint32 =
  inc calls
  code
let monitor = initResetMonitor(check,contextGuard)
doAssert monitor.supported and not monitor.poll() and calls == 1
code = 0x8253
var alias = monitor
doAssert alias.poll() and monitor.isLost and monitor.resetCode == code
for i in 0..<100: doAssert monitor.poll()
doAssert calls == 2 # no driver queries after observing loss
var rejected = false
try: contextGuard.requireContext()
except ValueError: rejected = true
doAssert rejected
let unsupported = initResetMonitor()
doAssert not unsupported.supported and not unsupported.poll()
unsupported.markLost(0)
doAssert unsupported.poll() and unsupported.resetCode == 0x8255
let badScopes = newContextScopes()
let failingCheck: ResetCheck = proc():uint32 =
  raise newException(ValueError,"injected reset callback")
let throwing = initResetMonitor(failingCheck,badScopes)
rejected = false
try: discard throwing.poll()
except ValueError: rejected = true
doAssert rejected and throwing.isLost
rejected = false
try: badScopes.requireContext()
except ValueError: rejected = true
doAssert rejected
var budget = initRecoveryBudget(3)
for i in 1..3:
  doAssert budget.consume() and budget.attempts == i
for i in 0..<100: doAssert not budget.consume()
doAssert budget.attempts == 3
var none: RecoveryBudget
doAssert not none.consume()
for limit in [-1,101]:
  rejected = false
  try: discard initRecoveryBudget(limit)
  except ValueError: rejected = true
  doAssert rejected
let healthyCheck: ResetCheck = proc():uint32 = 0
let fresh = initResetMonitor(healthyCheck,newContextScopes())
doAssert not fresh.poll() and monitor.isLost
echo "Reset monitor latch / scope invalidation / unsupported / failure / recovery budget PASS"

when not defined(js):
  import softgfx/recovery/gles as resetGl
  var extensions: cstring = "GL_EXT_robustness"
  var apiVersion: cstring = "OpenGL ES 3.0 mock"
  var statusCalls, statusResolutions, strategyReads: int
  proc mockString(name:uint32): cstring {.cdecl.} =
    if name == 0x1F03: extensions else: apiVersion
  proc mockInteger(name:uint32; value:ptr int32) {.cdecl.} =
    doAssert name == 0x8256
    inc strategyReads
    value[] = 0x8252
  proc mockStatus(): uint32 {.cdecl.} =
    inc statusCalls
    0
  proc mockResolver(name:cstring): pointer {.cdecl.} =
    case $name
    of "glGetString": cast[pointer](mockString)
    of "glGetIntegerv": cast[pointer](mockInteger)
    of "glGetGraphicsResetStatus", "glGetGraphicsResetStatusKHR", "glGetGraphicsResetStatusEXT":
      inc statusResolutions
      cast[pointer](mockStatus)
    else: nil
  var probe = resetGl.resetProbe(mockResolver)
  doAssert probe.source == "GL_EXT_robustness" and probe.notificationStrategy == 0x8252
  doAssert statusCalls == 0 and strategyReads == 1
  doAssert probe.check() == 0 and statusCalls == 1
  extensions = "prefixGL_KHR_robustness GL_EXT_robustness_suffix"
  let before = statusResolutions
  probe = resetGl.resetProbe(mockResolver)
  doAssert probe.check == nil and probe.source == "unavailable" and statusResolutions == before
  extensions = "GL_KHR_robustness GL_EXT_robustness"
  probe = resetGl.resetProbe(mockResolver)
  doAssert probe.source == "GL_KHR_robustness"
  extensions = ""
  apiVersion = "OpenGL ES 3.2 mock"
  probe = resetGl.resetProbe(mockResolver)
  doAssert probe.source == "GLES_3_2_core" and probe.check != nil
  rejected = false
  try: discard resetGl.resetProbe(nil)
  except ValueError: rejected = true
  doAssert rejected
  echo "GLES reset adapter exact extension gating / advertised API resolution PASS"
