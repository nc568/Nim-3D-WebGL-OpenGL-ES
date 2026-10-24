## Explicit per-context arbitration. Host shares ONE guard across cooperating users.
## No GL calls, global registry, thread safety, or per-claim allocation.
type
  ScopeKind* = enum frameScope, queryScope
  ScopeOwner* = ref object
  ContextScopes* = ref object
    valid: bool
    owners: array[ScopeKind,ScopeOwner]

proc newContextScopes*(): ContextScopes = ContextScopes(valid:true)
proc newScopeOwner*(): ScopeOwner = ScopeOwner()

proc requireContext*(scopes: ContextScopes) =
  if not scopes.isNil and not scopes.valid:
    raise newException(ValueError,"Context scopes are invalid; recreate after recovery")

proc requireAvailable*(scopes: ContextScopes; kind: ScopeKind; owner: ScopeOwner) =
  scopes.requireContext()
  if not scopes.isNil and not scopes.owners[kind].isNil and scopes.owners[kind] != owner:
    raise newException(ValueError,"Context scope is owned by another resource")

proc claim*(scopes: ContextScopes; kind: ScopeKind; owner: ScopeOwner) =
  if scopes.isNil: return # compatibility path; no arbitration
  if owner.isNil: raise newException(ValueError,"Missing scope owner")
  scopes.requireAvailable(kind,owner)
  scopes.owners[kind] = owner

proc release*(scopes: ContextScopes; kind: ScopeKind; owner: ScopeOwner) =
  if not scopes.isNil and scopes.owners[kind] == owner:
    scopes.owners[kind] = nil

proc invalidate*(scopes: ContextScopes) =
  if scopes.isNil: return
  scopes.valid = false
  for kind in ScopeKind: scopes.owners[kind] = nil
