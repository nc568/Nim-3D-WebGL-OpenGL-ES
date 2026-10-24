## CPU restore source shared explicitly by the host and its renderer.
## Owner IDs are bytes. Row zero maps to v=0; no implicit image flip.
type
  Palette* = array[256*4, uint8] ## Linear RGBA8; alpha reserved (opaque rendering).
  OwnerMap* = ref object
    w, h: int
    cells: seq[uint8]
    colors: Palette

func defaultPalette*(): Palette =
  for i in 0..255:
    result[i*4] = 70
    result[i*4+1] = 95
    result[i*4+2] = 80
    result[i*4+3] = 255

proc newOwnerMap*(width, height: int; palette = defaultPalette()): OwnerMap =
  # Deliberate CPU budget; also checked against the actual GPU limit during upload.
  if width <= 0 or height <= 0 or width > 4096 or height > 4096:
    raise newException(ValueError, "Owner map dimensions must be 1..4096")
  OwnerMap(w: width, h: height, cells: newSeq[uint8](width*height), colors: palette)

func width*(m: OwnerMap): int = m.w
func height*(m: OwnerMap): int = m.h
proc pixels*(m: OwnerMap): seq[uint8] =
  ## Snapshot for initial upload; changes use applyDelta, not this copy.
  result = newSeq[uint8](m.cells.len)
  for i,v in m.cells: result[i] = v
func palette*(m: OwnerMap): Palette = m.colors

proc checkDelta*(m: OwnerMap; x,y,w,h: int; data: openArray[uint8]) =
  if m.isNil: raise newException(ValueError, "Owner map is nil")
  # Subtraction rather than x+w prevents integer overflow on native and JS.
  if x < 0 or y < 0 or w <= 0 or h <= 0 or w > m.w or h > m.h or
      x > m.w-w or y > m.h-h or data.len != w*h:
    raise newException(ValueError, "Invalid tightly packed owner rectangle")

proc applyDelta*(m: OwnerMap; x,y,w,h: int; data: openArray[uint8]) =
  m.checkDelta(x,y,w,h,data)
  for row in 0..<h:
    for col in 0..<w: m.cells[(y+row)*m.w+x+col] = data[row*w+col]
