## Included by culling.nim to share exactly the same conservative bounds/planes.
## Import softgfx/culling, not this implementation file.
type
  SpatialGrid* = object
    region: Bounds
    divisions: array[3,int]
    occupied: seq[int] # bounded active-cell IDs, in first-encounter order
    occupiedCount: int
    heads, links: seq[int] # index+1, zero means absent
    boxes, cells: seq[Bounds]
    marks: seq[bool]
    capacity, count: int
    ready: bool
  GridQueryStats* = object
    cellVisits*, occupiedCells*, candidateCells*, instanceTests*, visibleInstances*: int
    orderScans*, orderComparisons*: int

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
  result.occupied = newSeq[int](min(cellCount,capacity))
  result.heads = newSeq[int](cellCount)
  result.cells = newSeq[Bounds](cellCount)
  result.links = newSeq[int](capacity)
  result.boxes = newSeq[Bounds](capacity)
  result.marks = newSeq[bool](capacity)

proc clearOccupied(grid: var SpatialGrid) =
  for slot in 0..<grid.occupiedCount: grid.heads[grid.occupied[slot]] = 0
  grid.occupiedCount = 0

proc rebuild*(grid: var SpatialGrid; local: Bounds; items: openArray[Instance]) =
  ## Rebuild after ANY pose/local-bound/order/count change. Validation is atomic.
  ## Cell bounds are unions, NOT geometric cell limits: outliers/large objects safe.
  if grid.capacity == 0: raise newException(ValueError,"Uninitialized spatial grid")
  local.validateLocal()
  items.validate(grid.capacity)
  clearOccupied(grid)
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
    if grid.heads[cell] == 0:
      grid.occupied[grid.occupiedCount] = cell
      inc grid.occupiedCount
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

proc siftIndices(indices: var seq[int]; root, count: int; comparisons: var int) =
  var at = root
  while at*2+1 < count:
    var child = at*2+1
    if child+1 < count:
      inc comparisons
      if indices[child] < indices[child+1]: inc child
    inc comparisons
    if indices[at] >= indices[child]: break
    swap(indices[at],indices[child])
    at = child

proc sortIndexPrefix(indices: var seq[int]; count: int; comparisons: var int) =
  ## In-place heapsort: no slices, recursion or allocation; ascending source order.
  if count < 2: return
  for root in countdown(count div 2-1,0): siftIndices(indices,root,count,comparisons)
  for last in countdown(count-1,1):
    swap(indices[0],indices[last])
    siftIndices(indices,0,last,comparisons)

proc collectVisible*(f: Frustum; grid: var SpatialGrid; indices: var seq[int];
                     stats: var GridQueryStats): int =
  ## Stable source-order prefix, same as flat collectVisible. No allocation/resize.
  ## Cached snapshot must still correspond to the uploaded instances.
  if not f.ready or not grid.ready: raise newException(ValueError,"Uninitialized grid/frustum")
  if indices.len < grid.count: raise newException(ValueError,"Visibility buffer too small")
  stats.cellVisits = 0
  stats.occupiedCells = 0
  stats.candidateCells = 0
  stats.instanceTests = 0
  stats.visibleInstances = 0
  stats.orderScans = 0
  stats.orderComparisons = 0
  for slot in 0..<grid.occupiedCount:
    let cell = grid.occupied[slot]
    inc stats.cellVisits
    inc stats.occupiedCells
    if not f.intersects(grid.cells[cell]): continue
    inc stats.candidateCells
    var entry = grid.heads[cell]
    while entry != 0:
      let i = entry-1
      inc stats.instanceTests
      if f.intersects(grid.boxes[i]):
        indices[result] = i
        inc result
      entry = grid.links[i]
  # Sparse hits: sort only the selected prefix. Dense hits: linear stable scan.
  # Marks are set/cleared only on the dense path; no O(N) clear before every query.
  var levels = 1
  var remaining = result
  while remaining > 1:
    inc levels
    remaining = remaining div 2
  if result <= grid.count div (2*levels):
    sortIndexPrefix(indices,result,stats.orderComparisons)
  else:
    for i in 0..<result: grid.marks[indices[i]] = true
    var written = 0
    for i in 0..<grid.count:
      inc stats.orderScans
      if grid.marks[i]:
        grid.marks[i] = false
        indices[written] = i
        inc written
  stats.visibleInstances = result
