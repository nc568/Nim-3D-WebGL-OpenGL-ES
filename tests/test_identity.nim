import softgfx/[identity, instances, motion]

var scratch = initIdentityScratch(8)
let oldIds = @[10'i32,20,30]
let old = @[instance([1'f32,0,0]),instance([2'f32,0,0]),instance([3'f32,0,0])]
let ids = @[30'i32,40,10]
let current = @[instance([30'f32,0,0]),instance([40'f32,0,0]),instance([10'f32,0,0])]
var aligned = newSeq[Instance](3)
let counts = alignHistory(oldIds,old,ids,current,[],aligned,scratch)
doAssert counts.matched == 2 and counts.spawned == 1 and counts.despawned == 1
var rendered = newSeq[Instance](3)
interpolateInstances(aligned,current,0.5,rendered)
doAssert rendered[0].position[0] == 16.5 and rendered[1] == current[1]
doAssert rendered[2].position[0] == 5.5
let reset = alignHistory(oldIds,old,ids,current,[true,false,false],aligned,scratch)
doAssert reset.reset == 1 and aligned[0] == current[0]
# Alias-safe arbitrary permutation, not only same-index writes.
var alias = old
let permuted = alignHistory(oldIds,alias,[30'i32,10,20],current,[],alias,scratch)
doAssert permuted.matched == 3 and alias == @[old[2],old[0],old[1]]
let saved = aligned
for duplicate in [@[30'i32,30,10],@[-1'i32,40,10]]:
  var rejected = false
  try: discard alignHistory(oldIds,old,duplicate,current,[],aligned,scratch)
  except ValueError: rejected = true
  doAssert rejected and aligned == saved
var rejected = false
try: discard alignHistory([10'i32,10,30],old,ids,current,[],aligned,scratch)
except ValueError: rejected = true
doAssert rejected and aligned == saved
var invalid = current
invalid[2].scale = 0
rejected = false
try: discard alignHistory(oldIds,old,ids,invalid,[],aligned,scratch)
except ValueError: rejected = true
doAssert rejected and aligned == saved
# Reuse after invalid requests and complete despawn/spawn.
discard alignHistory(oldIds,old,ids,current,[],aligned,scratch)
var empty: seq[Instance]
let removed = alignHistory(oldIds,old,[],empty,[],empty,scratch)
doAssert removed.despawned == 3
let spawned = alignHistory([],empty,ids,current,[],aligned,scratch)
doAssert spawned.spawned == 3 and aligned == current
# Collision chains and upper ID bound (portable JS int32).
let collisions = @[0'i32,32,64,96,high(int32)]
var poses = newSeq[Instance](5)
var target = newSeq[Instance](5)
for i in 0..<5: poses[i] = instance([float32(i),0,0])
for pass in 0..<100:
  let reverse = @[high(int32),96'i32,64,32,0]
  discard alignHistory(collisions,poses,reverse,poses,[],target,scratch)
  for i in 0..<5: doAssert target[i] == poses[4-i]
echo "Identity reorder / spawn / despawn / reset / aliases / collisions / atomic validation PASS"
var currentAlias = current
discard alignHistory(oldIds,old,ids,currentAlias,[],currentAlias,scratch)
doAssert currentAlias == @[old[2],current[1],old[0]]
for badLength in [0,2,4]:
  var wrong = newSeq[Instance](badLength)
  rejected = false
  try: discard alignHistory(oldIds,old,ids,current,[],wrong,scratch)
  except ValueError: rejected = true
  doAssert rejected
rejected = false
try: discard alignHistory(oldIds,old,ids,current,[true],aligned,scratch)
except ValueError: rejected = true
doAssert rejected
var uninitialized: IdentityScratch
rejected = false
try: discard alignHistory(oldIds,old,ids,current,[],aligned,uninitialized)
except ValueError: rejected = true
doAssert rejected
for badCapacity in [0,MaxInstances+1]:
  rejected = false
  try: discard initIdentityScratch(badCapacity)
  except ValueError: rejected = true
  doAssert rejected
var small = initIdentityScratch(2)
rejected = false
try: discard alignHistory(oldIds,old,ids,current,[],aligned,small)
except ValueError: rejected = true
doAssert rejected
# Deterministic permutations + mixed spawn/despawn, checked against linear oracle.
var many = initIdentityScratch(257)
var aIds, bIds: seq[EntityId]
var a, b, history: seq[Instance]
aIds.setLen(257); bIds.setLen(257)
a.setLen(257); b.setLen(257); history.setLen(257)
for i in 0..<257:
  aIds[i] = int32(i*31)
  a[i] = instance([float32(i),0,0])
  b[i] = instance([float32(1000+i),0,0])
for iteration in 1..20:
  for i in 0..<257:
    bIds[i] = if i mod 7 == 0: int32(100000+i) else: aIds[(i*iteration) mod 257]
  discard alignHistory(aIds,a,bIds,b,[],history,many)
  for i in 0..<257:
    var found = -1
    for j in 0..<257:
      if aIds[j] == bIds[i]: found = j
    doAssert history[i] == (if found < 0: b[i] else: a[found])
echo "Identity capacity/length guards and 5140 linear-oracle comparisons PASS"
