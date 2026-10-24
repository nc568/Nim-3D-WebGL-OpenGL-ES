## Included by culling.nim to share exactly the same conservative bounds/planes.
## Import softgfx/culling, not this implementation file.
type
  SpatialGrid* = object
    region: Bounds
    divisions: array[3,int]
    heads, links: seq[int] # index+1, zero means absent
    boxes, cells: seq[Bounds]
    marks: seq[bool]
    capacity, count: int
    ready: bool
  GridQueryStats* = object
    occupiedCells*, candidateCells*, instanceTests*, visibleInstances*: int

proc initSpatialGrid*(region: Bounds; divisions: array[3,int]; capacity: int): SpatialGrid =
  region.validate()
  if capacity < 1 or capacity > MaxInstances:
    raise newException(ValueError,"Invalid spatial grid capacity")
  var cellCount = 1
  for axis in 0..2:
    if divisions[axis] < 1 or divisions[axis] > 32 or region.upper[axis] <= region.lower[axis]:
      raise newException(ValueError,"Grid requires positive region spans and divisions 1..32")
    cellCount *= divisions[axis]
  result.region = region
  result.divisions = divisions
  result.capacity = capacity
  result.heads = newSeq[int](cellCount)
  result.cells = newSeq[Bounds](cellCount)
  result.links = newSeq[int](capacity)
  result.boxes = newSeq[Bounds](capacity)
  result.marks = newSeq[bool](capacity)

proc rebuild*(grid: var SpatialGrid; local: Bounds; items: openArray[Instance]) =
  ## Rebuild after ANY pose/local-bound/order/count change. Validation is atomic.
  ## Cell bounds are unions, NOT geometric cell limits: outliers/large objects safe.
  if grid.capacity == 0: raise newException(ValueError,"Uninitialized spatial grid")
  local.validateLocal()
  items.validate(grid.capacity)
  for cell in 0..<grid.heads.len: grid.heads[cell] = 0
  for i in 0..<items.len:
    local.transformedInto(items[i],grid.boxes[i])
    var cell = 0
    var stride = 1
    for axis in 0..2:
      let center = grid.boxes[i].lower[axis]*0.5+grid.boxes[i].upper[axis]*0.5
      let fraction = clamp((center-grid.region.lower[axis]) /
        (grid.region.upper[axis]-grid.region.lower[axis]),0.0,1.0)
      let coordinate = min(grid.divisions[axis]-1,int(fraction*float64(grid.divisions[axis])))
      cell += coordinate*stride
      stride *= grid.divisions[axis]
    for axis in 0..2:
      if grid.heads[cell] == 0:
        grid.cells[cell].lower[axis] = grid.boxes[i].lower[axis]
        grid.cells[cell].upper[axis] = grid.boxes[i].upper[axis]
      else:
        grid.cells[cell].lower[axis] = min(grid.cells[cell].lower[axis],grid.boxes[i].lower[axis])
        grid.cells[cell].upper[axis] = max(grid.cells[cell].upper[axis],grid.boxes[i].upper[axis])
    grid.links[i] = grid.heads[cell]
    grid.heads[cell] = i+1
  grid.count = items.len
  grid.ready = true

proc collectVisible*(f: Frustum; grid: var SpatialGrid; indices: var seq[int];
                     stats: var GridQueryStats): int =
  ## Stable source-order prefix, same as flat collectVisible. No allocation/resize.
  ## Cached snapshot must still correspond to the uploaded instances.
  if not f.ready or not grid.ready: raise newException(ValueError,"Uninitialized grid/frustum")
  if indices.len < grid.count: raise newException(ValueError,"Visibility buffer too small")
  stats.occupiedCells = 0
  stats.candidateCells = 0
  stats.instanceTests = 0
  stats.visibleInstances = 0
  for i in 0..<grid.count: grid.marks[i] = false
  for cell in 0..<grid.heads.len:
    if grid.heads[cell] == 0: continue
    inc stats.occupiedCells
    if not f.intersects(grid.cells[cell]): continue
    inc stats.candidateCells
    var entry = grid.heads[cell]
    while entry != 0:
      let i = entry-1
      inc stats.instanceTests
      grid.marks[i] = f.intersects(grid.boxes[i])
      entry = grid.links[i]
  for i in 0..<grid.count:
    if grid.marks[i]:
      indices[result] = i
      inc result
  stats.visibleInstances = result
