import softgfx/[recovery, scopes]
var calls = 0
var code = 0'u32
let scopes = newContextScopes()
let check: ResetCheck = proc():uint32 =
  inc calls
  code
let monitor = initResetMonitor(check,scopes)
doAssert monitor.supported and not monitor.poll() and calls == 1
code = 0x8253
var alias = monitor
doAssert alias.poll() and monitor.isLost and monitor.resetCode == code
for i in 0..<100: doAssert monitor.poll()
doAssert calls == 2 # no driver queries after observing loss
var rejected = false
try: scopes.requireContext()
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
