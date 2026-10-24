## Backend-neutral, latched context health. No GL calls after an observed failure.
import ./scopes

type
  ResetCheck* = proc(): uint32 {.closure.}
  ResetMonitor* = ref object
    check: ResetCheck
    scopes: ContextScopes
    failed: bool
    code: uint32
  RecoveryBudget* = object
    limit, used: int

proc initResetMonitor*(check: ResetCheck = nil; scopes: ContextScopes = nil): ResetMonitor =
  scopes.requireContext()
  ResetMonitor(check:check,scopes:scopes)
proc supported*(monitor: ResetMonitor): bool = not monitor.isNil and monitor.check != nil
proc isLost*(monitor: ResetMonitor): bool = not monitor.isNil and monitor.failed
proc resetCode*(monitor: ResetMonitor): uint32 =
  if monitor.isNil: 0'u32 else: monitor.code
proc markLost*(monitor: ResetMonitor; code = 0x8255'u32) =
  ## Also usable by platform loss callbacks. Does NOT destroy GPU/platform handles.
  if monitor.isNil: raise newException(ValueError,"Missing reset monitor")
  if not monitor.failed:
    monitor.failed = true
    monitor.code = if code == 0: 0x8255'u32 else: code
    monitor.scopes.invalidate()
proc poll*(monitor: ResetMonitor): bool =
  ## false = no reset observed, NOT proof of hardware health if unsupported.
  if monitor.isNil: raise newException(ValueError,"Missing reset monitor")
  if monitor.failed: return true
  monitor.scopes.requireContext()
  if monitor.check == nil: return false
  try:
    let code = monitor.check()
    if code != 0: monitor.markLost(code)
  except:
    monitor.markLost() # unknown driver state; caller must not render/delete
    raise
  monitor.failed
proc initRecoveryBudget*(maximum = 3): RecoveryBudget =
  if maximum < 0 or maximum > 100: raise newException(ValueError,"Invalid recovery budget")
  RecoveryBudget(limit:maximum)
proc consume*(budget: var RecoveryBudget): bool =
  ## Lifetime cap; no automatic reset that could hide a persistent reset storm.
  if budget.used >= budget.limit: return false
  inc budget.used
  true
proc attempts*(budget: RecoveryBudget): int = budget.used
