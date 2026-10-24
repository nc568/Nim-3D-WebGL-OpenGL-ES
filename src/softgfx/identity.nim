## Snapshot identity alignment, independent of rendering and simulation ownership.
import ./instances

type
  EntityId* = int32
  IdentityScratch* = object
    previousSlots, currentSlots: seq[int] # index + 1; zero is vacant
    staged: seq[Instance]
    capacity: int
  IdentityChanges* = object
    matched*, spawned*, despawned*, reset*: int

proc initIdentityScratch*(capacity: int): IdentityScratch =
  if capacity < 1 or capacity > MaxInstances:
    raise newException(ValueError,"Identity capacity outside batch budget")
  var slots = 1
  while slots < capacity*4: slots *= 2
  result.capacity = capacity
  result.previousSlots = newSeq[int](slots)
  result.currentSlots = newSeq[int](slots)
  result.staged = newSeq[Instance](capacity)

proc slot(ids: openArray[EntityId]; table: seq[int]; id: EntityId): int =
  # Bounded load <= 25%. Linear probing; hostile colliding IDs can be quadratic.
  result = int(id) mod table.len
  while table[result] != 0 and ids[table[result]-1] != id:
    result = (result+1) mod table.len

proc indexIds(ids: openArray[EntityId]; table: var seq[int]) =
  for i in 0..<table.len: table[i] = 0
  for i in 0..<ids.len:
    if ids[i] < 0: raise newException(ValueError,"Entity IDs must be nonnegative int32")
    let at = slot(ids,table,ids[i])
    if table[at] != 0: raise newException(ValueError,"Duplicate entity ID")
    table[at] = i+1

proc copyPose(source: Instance; target: var Instance) =
  for axis in 0..2:
    target.position[axis] = source.position[axis]
    target.tint[axis] = source.tint[axis]
  target.yaw = source.yaw
  target.scale = source.scale

proc alignHistory*(previousIds: openArray[EntityId]; previous: openArray[Instance];
                   currentIds: openArray[EntityId]; current: openArray[Instance];
                   reset: openArray[bool]; aligned: var seq[Instance];
                   scratch: var IdentityScratch): IdentityChanges =
  ## Output follows current order. Spawn/reset snaps to current; despawn disappears.
  ## reset is empty (none) or current.len. IDs cannot be reused across lifetimes
  ## without reset/new generation. Validation failure leaves aligned unchanged.
  ## All output writes are staged, allowing aliases with either input snapshot.
  if scratch.capacity == 0 or previousIds.len != previous.len or
      currentIds.len != current.len or aligned.len != current.len or
      (reset.len != 0 and reset.len != current.len):
    raise newException(ValueError,"Invalid identity storage/snapshot lengths")
  previous.validate(scratch.capacity)
  current.validate(scratch.capacity)
  indexIds(previousIds,scratch.previousSlots)
  indexIds(currentIds,scratch.currentSlots)
  for i in 0..<current.len:
    let at = slot(previousIds,scratch.previousSlots,currentIds[i])
    let found = scratch.previousSlots[at]-1
    if found >= 0:
      inc result.matched
      if reset.len != 0 and reset[i]:
        inc result.reset
        copyPose(current[i],scratch.staged[i])
      else:
        copyPose(previous[found],scratch.staged[i])
    else:
      inc result.spawned
      copyPose(current[i],scratch.staged[i])
  result.despawned = previous.len-result.matched
  for i in 0..<current.len: copyPose(scratch.staged[i],aligned[i])
